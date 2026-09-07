import type { ExtractedTask } from "./types";

const SYSTEM_PROMPT = `You classify a single incoming message (an email or a chat message) for a personal
assistant app called AiMe. Decide whether it contains something the user needs to act on:
a bill, an appointment to confirm, a document to sign, a reminder request, or a direct
question waiting for a reply. Newsletters, marketing, and messages with no action are not actionable.

Respond with ONLY a JSON object, no prose, no markdown fences, matching exactly this shape:
{"isActionable": boolean, "title": string, "type": "bill"|"message"|"document"|"appointment"|"task",
 "category": "personal"|"work"|"finance"|"appointments"|"purchases",
 "priority": "urgent"|"high"|"normal"|"low", "amount": number|null, "currency": string|null,
 "dueDate": string|null, "whySummary": string}

"whySummary" is one short sentence explaining, in plain language, what in the message caused you to
create this task (e.g. "Contains an amount, a due date, and a payment link."). If isActionable is
false, still return valid JSON with isActionable:false and the other fields as null/empty.`;

// Haiku is intentionally used here: this call runs once per candidate message on every sync,
// so cost and latency matter far more than raw capability for a one-sentence classification task.
const MODEL = "claude-haiku-4-5-20251001";

export async function extractTask(sourceLabel: string, text: string): Promise<ExtractedTask | null> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY is not set");

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 300,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: `Source: ${sourceLabel}\n\nMessage:\n${text.slice(0, 4000)}` }],
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
    return parsed;
  } catch {
    console.error("Could not parse extraction response:", raw);
    return null;
  }
}
