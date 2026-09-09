import type { ExtractedTask } from "./types";

const SYSTEM_PROMPT = `You classify a single incoming message (an email or a chat message) for a personal
assistant app called AiMe. Right now, scope is narrowed on purpose to two kinds of things: bills/payments, and
important messages that genuinely need a response or action (a document to sign, a direct question awaiting a
reply, a real deadline). Do NOT flag appointments, calendar invitations, birthdays, RSVPs, or generic reminders as
actionable right now, even if they'd normally qualify — that's out of scope for this pass. Pure marketing/promotional
email and routine notification digests (e.g. "you have 5 new messages") are never actionable.

You may be given a list of candidate links found in the message body. If this looks like a bill and one of those
links is plausibly the payment/action page (e.g. its text or URL path mentions pay, payment, invoice, bill, account,
checkout), set "actionUrl" to that exact URL, copied verbatim from the list — never invent or guess a URL that
wasn't given to you. If no candidate links were given, or none look like the right one, set "actionUrl" to null.

Respond with ONLY a JSON object, no prose, no markdown fences, matching exactly this shape:
{"isActionable": boolean, "title": string, "type": "bill"|"message"|"document"|"task",
 "category": "personal"|"work"|"finance"|"purchases",
 "priority": "urgent"|"high"|"normal"|"low", "amount": number|null, "currency": string|null,
 "dueDate": string|null, "actionUrl": string|null, "whySummary": string}

"whySummary" is one short sentence explaining, in plain language, what in the message caused you to
create this task (e.g. "Contains an amount, a due date, and a payment link."). If isActionable is
false, still return valid JSON with isActionable:false and the other fields as null/empty.

Write "title" and "whySummary" in the same language as the source message — if the message is in
Hebrew, respond in Hebrew; if it's in English, respond in English.`;

// Haiku is intentionally used here: this call runs once per candidate message on every sync,
// so cost and latency matter far more than raw capability for a one-sentence classification task.
const MODEL = "claude-haiku-4-5-20251001";

export async function extractTask(sourceLabel: string, text: string, links: string[] = []): Promise<ExtractedTask | null> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY is not set");

  const linksBlock = links.length
    ? `\n\nCandidate links found in this message:\n${links.map((l) => `- ${l}`).join("\n")}`
    : "";

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 400,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: `Source: ${sourceLabel}\n\nMessage:\n${text.slice(0, 4000)}${linksBlock}` }],
    }),
  });

  if (!res.ok) {
    console.error("Anthropic extraction call failed", res.status, await res.text().catch(() => ""));
    return null;
  }

  const data = await res.json();
  const raw: string = data?.content?.find((b: any) => b.type === "text")?.text ?? "";
  const cleaned = raw.replace(/```json|```/g, "").trim();

  try {
    const parsed = JSON.parse(cleaned) as ExtractedTask;
    // Guard against a hallucinated URL slipping through despite the instruction —
    // only keep actionUrl if it's one of the links we actually gave the model.
    if (parsed.actionUrl && !links.includes(parsed.actionUrl)) {
      parsed.actionUrl = null;
    }
    return parsed;
  } catch {
    console.error("Could not parse extraction response:", raw);
    return null;
  }
}
