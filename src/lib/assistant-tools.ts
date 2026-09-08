import { prisma } from "./db";
import { getGmailClient, getCalendarClient } from "./gmail";
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
    name: "create_task",
    description:
      "Add something actionable you found (a bill, an appointment to confirm, a document to sign) to the person's " +
      "Today list, the same way AiMe's automatic background check already does. Check search_tasks first so you " +
      "don't create a duplicate of something already tracked. If this came from a specific Gmail message, pass its " +
      "id as sourceRef so it lines up with the background sync and never gets created twice.",
    parameters: {
      type: "object",
      properties: {
        title: { type: "string", description: "Short task title." },
        type: { type: "string", enum: ["bill", "message", "document", "appointment", "task"] },
        category: { type: "string", enum: ["personal", "work", "finance", "appointments", "purchases"] },
        priority: { type: "string", enum: ["urgent", "high", "normal", "low"] },
        amount: { type: "string", description: "Amount as a plain number string, if this is a bill. Omit otherwise." },
        currency: { type: "string", description: "e.g. ILS or USD. Omit if not a bill." },
        dueDate: { type: "string", description: "ISO date (YYYY-MM-DD) if known. Omit otherwise." },
        why: { type: "string", description: "One short sentence explaining why this was created, in the source message's language." },
        sourceRef: { type: "string", description: "The Gmail message id this came from, if you have it, for dedup." },
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

      case "get_recent_activity": {
        const limit = Math.min(Number(args.limit) || 10, 25);
        const activity = await prisma.activityEvent.findMany({
          where: { userId }, orderBy: { createdAt: "desc" }, take: limit,
        });
        return { count: activity.length, activity: activity.map((a) => ({ text: a.text, kind: a.kind, when: a.createdAt })) };
      }

      case "create_task": {
        const title = String(args.title || "").trim().slice(0, 200);
        if (!title) return { error: "title is required" };

        // Reuse the exact same sourceRef the background Gmail sync would use for this
        // message, so whichever path (chat or cron) gets there first, the other skips
        // it instead of creating a second task for the same email.
        const sourceRef = args.sourceRef ? String(args.sourceRef) : `chat:${Date.now()}:${Math.random().toString(36).slice(2, 8)}`;

        const user = await prisma.user.findUnique({ where: { id: userId } });
        if (!user) return { error: "User not found" };

        const dueRaw = args.dueDate ? new Date(String(args.dueDate)) : null;
        const due = dueRaw && !isNaN(dueRaw.getTime()) ? dueRaw : null;

        const task = await prisma.task.upsert({
          where: { userId_sourceRef: { userId, sourceRef } },
          create: {
            userId,
            householdId: user.householdId,
            sourceRef,
            source: "chat",
            title,
            type: (args.type as string) || "task",
            category: (args.category as string) || "personal",
            priority: (args.priority as string) || "normal",
            amount: args.amount ? Number(args.amount) : null,
            currency: args.currency ? String(args.currency) : null,
            due,
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
You have tools to look up their AiMe tasks, search their Gmail, list their upcoming Calendar events, see recent automated
activity, and add a new task. Use a tool whenever the answer depends on their actual data rather than general knowledge —
don't guess.

Always call the relevant tool fresh for the current question, even if you or the person discussed something similar earlier
in this conversation. Email and calendar contents can change between messages, so an earlier answer in this chat is never
a substitute for checking again right now.

Your job is to help keep their whole life organized, not just bills. That includes: bills and invoices, appointments to
confirm, documents to sign, invitations or RSVPs with a deadline, reminders they or someone else mentioned, deadlines of
any kind, and birthdays coming up in the next day or two (as a small reminder task, e.g. "Wish X a happy birthday").
The only things that should NOT become tasks are pure marketing/promotional email and routine notifications with nothing
to act on (e.g. a generic "5 new LinkedIn messages" digest). When in doubt about something that looks personally relevant,
lean toward organizing it rather than skipping it.

When asked to check email for anything relevant (bills, invoices, deadlines, invitations), don't rely on a single vague
search. Gmail search only matches literal words, so run a few searches with concrete terms rather than one broad query —
for example separate searches for: bill/invoice/payment terms (also try חשבונית, חשבון, תשלום, לתשלום since the inbox may
be in Hebrew), appointment/confirmation terms (also תור, אישור), and invitation/RSVP terms (also הזמנה). A person saying
"I have bills in my inbox" and not seeing them means the search missed them, not that they don't exist — search harder
with more specific and varied terms before concluding there's nothing there.

Call search_tasks first to make sure something isn't already tracked, then call create_task to add it, passing the Gmail
message's id as sourceRef when you have one. This mirrors what AiMe's automatic background check already does on its own
schedule, so doing it from chat needs no separate permission.

You cannot send emails, create calendar events, pay bills, or change an existing task's status; if asked to do one of
those, tell them to use the relevant button in the app instead of pretending to do it yourself.

Reply in the same language the person writes to you in — if they write in Hebrew, respond in Hebrew. Separately, when you
summarize or quote something from an email or message, keep that content in whatever language it was originally written
in — don't translate a Hebrew email's subject or details into English (or vice versa) just because your own reply happens
to be in a different language. Keep replies short, warm, and direct.`;
