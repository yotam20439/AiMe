import { prisma } from "./db";
import { getGmailClient, getCalendarClient, getMessageDetails } from "./gmail";
import { scanGmailForIntegration } from "./scan";
import type { ToolDeclaration } from "./gemini";

// Every executor here is scoped to a single userId and is read-only — nothing in this
// file sends an email, creates a calendar event, or changes a task's status. That
// mirrors the rest of the app's rule that AI never takes a high-impact action silently.

export const ASSISTANT_TOOLS: ToolDeclaration[] = [
  {
    name: "search_tasks",
    description: "Search the person's AiMe tasks (bills, reminders, appointments, things waiting on someone).",
    parameters: {
      type: "object",
      properties: {
        status: { type: "string", enum: ["open", "waiting", "completed", "dismissed", "any"], description: "Filter by status, or 'any' for all." },
        query: { type: "string", description: "Optional text to match against the task title." },
      },
    },
  },
  {
    name: "search_gmail",
    description: "Search the person's Gmail. Use Gmail search syntax if helpful (e.g. 'from:amazon', 'newer_than:7d').",
    parameters: {
      type: "object",
      properties: {
        query: { type: "string", description: "Gmail search query." },
        maxResults: { type: "string", description: "Max messages to return, default 5." },
      },
      required: ["query"],
    },
  },
  {
    name: "search_calendar",
    description: "List the person's upcoming Google Calendar events in a date range.",
    parameters: {
      type: "object",
      properties: {
        daysAhead: { type: "string", description: "How many days ahead to look, default 7." },
      },
    },
  },
  {
    name: "run_email_scan",
    description:
      "The reliable way to check Gmail for bills and important messages, and actually add them to Today. This runs " +
      "the exact same process as AiMe's scheduled background check: it searches, reads each candidate email, and " +
      "creates properly-linked tasks itself — you don't need to call search_gmail, get_email_details, or create_task " +
      "yourself for this. Always use this tool (not manual searching) whenever asked to check for bills or scan the " +
      "inbox, since it guarantees every task it creates has a working link back to its email. Takes no arguments.",
    parameters: { type: "object", properties: {} },
  },
  {
    name: "get_recent_activity",
    description: "See what AiMe has recently found or done automatically for this person.",
    parameters: {
      type: "object",
      properties: {
        limit: { type: "string", description: "Max items, default 10." },
      },
    },
  },
  {
    name: "get_email_details",
    description:
      "Get the full body and any real links found in one specific email, by its Gmail message id (from a " +
      "search_gmail result). Use this on a bill before create_task, to find the actual payment link — never " +
      "invent a URL, only ever use one returned by this tool.",
    parameters: {
      type: "object",
      properties: {
        messageId: { type: "string", description: "The Gmail message id, from search_gmail results." },
      },
      required: ["messageId"],
    },
  },
  {
    name: "create_task",
    description:
      "Add a bill or an important message to the person's Today list, the same way AiMe's automatic background " +
      "check already does. Check search_tasks first so you don't create a duplicate of something already tracked. " +
      "If this came from an email, you MUST pass its id (from search_gmail's results) as sourceRef — never skip this, " +
      "it costs no extra tool call and without it the task can't link back to the source at all, making it useless. " +
      "This also lines up with the background sync so the same email never becomes two tasks. For bills, call " +
      "get_email_details first and pass the real payment link " +
      "as actionUrl if one exists.",
    parameters: {
      type: "object",
      properties: {
        title: { type: "string", description: "Short task title." },
        type: { type: "string", enum: ["bill", "message", "document", "task"] },
        category: { type: "string", enum: ["personal", "work", "finance", "purchases"] },
        priority: { type: "string", enum: ["urgent", "high", "normal", "low"] },
        amount: { type: "string", description: "Amount as a plain number string, if this is a bill. Omit otherwise." },
        currency: { type: "string", description: "e.g. ILS or USD. Omit if not a bill." },
        dueDate: { type: "string", description: "ISO date (YYYY-MM-DD) if known. Omit otherwise." },
        emailDate: { type: "string", description: "The date the source email was actually sent (from get_email_details or search_gmail), as an ISO date. Omit if unknown." },
        actionUrl: { type: "string", description: "A real payment/action link from get_email_details, if one exists. Never invent one." },
        why: { type: "string", description: "One short sentence explaining why this was created, in the source message's language." },
        sourceRef: { type: "string", description: "Required whenever this came from an email: the Gmail message id from search_gmail's results, verbatim." },
      },
      required: ["title"],
    },
  },
];

export function makeToolExecutor(userId: string) {
  return async function execute(name: string, args: Record<string, unknown>): Promise<Record<string, unknown>> {
    switch (name) {
      case "search_tasks": {
        const status = String(args.status || "open");
        const query = args.query ? String(args.query) : undefined;
        const tasks = await prisma.task.findMany({
          where: {
            userId,
            ...(status !== "any" ? { status } : {}),
            ...(query ? { title: { contains: query, mode: "insensitive" } } : {}),
          },
          orderBy: { due: "asc" },
          take: 15,
        });
        return {
          count: tasks.length,
          tasks: tasks.map((t) => ({
            title: t.title, status: t.status, priority: t.priority, due: t.due,
            amount: t.amount, currency: t.currency, source: t.source,
          })),
        };
      }

      case "search_gmail": {
        const integration = await prisma.integration.findUnique({ where: { userId_provider: { userId, provider: "google" } } });
        if (!integration || integration.status !== "connected") {
          return { error: "Gmail isn't connected for this person yet." };
        }
        const gmail = await getGmailClient(integration);
        const max = Math.min(Number(args.maxResults) || 5, 10);
        const list = await gmail.users.messages.list({ userId: "me", q: String(args.query || ""), maxResults: max });
        const ids = list.data.messages ?? [];
        const messages = await Promise.all(
          ids.map(async (m) => {
            const full = await gmail.users.messages.get({
              userId: "me", id: m.id!, format: "metadata", metadataHeaders: ["Subject", "From", "Date"],
            });
            const headers = full.data.payload?.headers ?? [];
            const get = (n: string) => headers.find((h) => h.name === n)?.value ?? "";
            return { id: m.id, subject: get("Subject"), from: get("From"), date: get("Date"), snippet: full.data.snippet ?? "" };
          })
        );
        return { count: messages.length, messages };
      }

      case "search_calendar": {
        const integration = await prisma.integration.findUnique({ where: { userId_provider: { userId, provider: "google" } } });
        if (!integration || integration.status !== "connected") {
          return { error: "Calendar isn't connected for this person yet." };
        }
        const calendar = await getCalendarClient(integration);
        const daysAhead = Number(args.daysAhead) || 7;
        const timeMin = new Date().toISOString();
        const timeMax = new Date(Date.now() + daysAhead * 86400000).toISOString();
        const res = await calendar.events.list({
          calendarId: "primary", timeMin, timeMax, singleEvents: true, orderBy: "startTime", maxResults: 20,
        });
        const events = (res.data.items ?? []).map((e) => ({
          title: e.summary, start: e.start?.dateTime || e.start?.date, end: e.end?.dateTime || e.end?.date,
        }));
        return { count: events.length, events };
      }

      case "run_email_scan": {
        const integration = await prisma.integration.findUnique({ where: { userId_provider: { userId, provider: "google" } } });
        if (!integration || integration.status !== "connected") {
          return { error: "Gmail isn't connected for this person yet." };
        }
        try {
          const result = await scanGmailForIntegration(integration);
          return result;
        } catch (err: any) {
          return { error: err?.message || "The scan failed." };
        }
      }

      case "get_recent_activity": {
        const limit = Math.min(Number(args.limit) || 10, 25);
        const activity = await prisma.activityEvent.findMany({
          where: { userId }, orderBy: { createdAt: "desc" }, take: limit,
        });
        return { count: activity.length, activity: activity.map((a) => ({ text: a.text, kind: a.kind, when: a.createdAt })) };
      }

      case "get_email_details": {
        const integration = await prisma.integration.findUnique({ where: { userId_provider: { userId, provider: "google" } } });
        if (!integration || integration.status !== "connected") {
          return { error: "Gmail isn't connected for this person yet." };
        }
        const messageId = String(args.messageId || "");
        if (!messageId) return { error: "messageId is required" };
        const gmail = await getGmailClient(integration);
        return getMessageDetails(gmail, messageId);
      }

      case "create_task": {
        const title = String(args.title || "").trim().slice(0, 200);
        if (!title) return { error: "title is required" };

        // If a real Gmail message id was provided, tag the source as gmail so the
        // dashboard's "open email" link actually works — only fall back to a
        // synthetic chat-only key when we truly don't have one.
        const providedRef = args.sourceRef ? String(args.sourceRef) : null;
        const sourceRef = providedRef || `chat:${Date.now()}:${Math.random().toString(36).slice(2, 8)}`;
        const source = providedRef ? "gmail" : "chat";

        const user = await prisma.user.findUnique({ where: { id: userId } });
        if (!user) return { error: "User not found" };

        const dueRaw = args.dueDate ? new Date(String(args.dueDate)) : null;
        const due = dueRaw && !isNaN(dueRaw.getTime()) ? dueRaw : null;
        const emailDateRaw = args.emailDate ? new Date(String(args.emailDate)) : null;
        const emailDate = emailDateRaw && !isNaN(emailDateRaw.getTime()) ? emailDateRaw : null;

        // Only accept an actionUrl that's a real, well-formed http(s) link — cheap guard
        // against a malformed or invented value slipping through.
        const rawUrl = args.actionUrl ? String(args.actionUrl) : null;
        const actionUrl = rawUrl && /^https?:\/\//.test(rawUrl) ? rawUrl : null;

        const task = await prisma.task.upsert({
          where: { userId_sourceRef: { userId, sourceRef } },
          create: {
            userId,
            householdId: user.householdId,
            sourceRef,
            source,
            title,
            type: (args.type as string) || "task",
            category: (args.category as string) || "personal",
            priority: (args.priority as string) || "normal",
            amount: args.amount ? Number(args.amount) : null,
            currency: args.currency ? String(args.currency) : null,
            due,
            actionUrl,
            emailDate,
            why: args.why ? String(args.why) : null,
            aiSummary: args.why ? String(args.why) : null,
          },
          update: {}, // already exists (created earlier by chat or by the background sync) — leave it alone
        });

        await prisma.activityEvent.create({
          data: { userId, text: `Added "${title}" from a chat check.`, kind: "tasks" },
        });

        return { created: true, taskId: task.id, title: task.title };
      }

      default:
        return { error: `Unknown tool: ${name}` };
    }
  };
}

export const ASSISTANT_SYSTEM_PROMPT = `You are the AiMe assistant, chatting directly with the person whose account this is.
You have tools to look up their AiMe tasks, run a reliable scan of their Gmail that creates properly-linked tasks itself,
search Gmail manually, get one email's full body and links, list their upcoming Calendar events, and see recent
automated activity. Use a tool whenever the answer depends on their actual data rather than general knowledge — don't guess.

Always call the relevant tool fresh for the current question, even if you or the person discussed something similar earlier
in this conversation. Email and calendar contents can change between messages, so an earlier answer in this chat is never
a substitute for checking again right now.

Scope is narrowed on purpose right now: organize bills/payments and important messages only — not appointments,
invitations, birthdays, or generic reminders, even though those might normally be worth tracking. The only things that
should never become tasks are pure marketing/promotional email and routine notification digests with nothing to act on.

Whenever asked to check for bills, check the inbox, or "check now" — call run_email_scan. Don't try to reconstruct that
process yourself with search_gmail, get_email_details, and create_task; that manual path has repeatedly produced tasks
with no working link back to their email, because it depends on correctly carrying an id across several separate steps.
run_email_scan does the searching, reading, and task-creation itself in one reliable step, and always produces a task
that can actually be opened and acted on. After calling it, summarize what it found and created using its result.

The manual search_gmail / get_email_details / create_task tools still exist for genuinely different questions — e.g. "did
David email me about the trip" or "add a task for that thing Sarah asked about" — where the person is pointing you at a
specific message rather than asking for a general inbox check. Even then, if you do create a task from an email this way,
sourceRef must be that message's real id from search_gmail's results — never omit it, never invent one.

You cannot send emails, create calendar events, pay bills, or change an existing task's status; if asked to do one of
those, tell them to use the relevant button in the app instead of pretending to do it yourself.

Reply in the same language the person writes to you in — if they write in Hebrew, respond in Hebrew. Separately, when you
summarize or quote something from an email or message, keep that content in whatever language it was originally written
in — don't translate a Hebrew email's subject or details into English (or vice versa) just because your own reply happens
to be in a different language. Keep replies short, warm, and direct.`;
