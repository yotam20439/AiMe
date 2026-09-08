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
            return { subject: get("Subject"), from: get("From"), date: get("Date"), snippet: full.data.snippet ?? "" };
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

      default:
        return { error: `Unknown tool: ${name}` };
    }
  };
}

export const ASSISTANT_SYSTEM_PROMPT = `You are the AiMe assistant, chatting directly with the person whose account this is.
You have read-only tools to look up their AiMe tasks, search their Gmail, list their upcoming Calendar events, and see recent
automated activity. Use a tool whenever the answer depends on their actual data rather than general knowledge — don't guess.

Always call the relevant tool fresh for the current question, even if you or the person discussed something similar earlier
in this conversation. Email and calendar contents can change between messages, so an earlier answer in this chat is never
a substitute for checking again right now.

You cannot send emails, create events, pay bills, or change any task's status; if asked to do one of those, tell them to use
the relevant button in the app instead of pretending to do it yourself. Reply in the same language the person writes to you
in — if they write in Hebrew, respond in Hebrew. Keep replies short, warm, and direct.`;
