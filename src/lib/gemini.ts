// Talks to Google's Gemini API (the classic generateContent endpoint — Google's newer
// "Interactions API" became their recommended path in mid-2026, but generateContent
// remains fully supported and is the simpler, more stable choice here).
//
// This module knows nothing about tasks, Gmail, or Calendar — it just runs the
// request/response loop and calls back into whatever tool executors it's given.
// See lib/assistant-tools.ts for what the assistant can actually look up.

export type GeminiPart =
  | { text: string }
  | { functionCall: { name: string; args: Record<string, unknown> }; thoughtSignature?: string }
  | { functionResponse: { name: string; response: Record<string, unknown> } };

export type GeminiContent = { role: "user" | "model"; parts: GeminiPart[] };

export type ToolDeclaration = {
  name: string;
  description: string;
  parameters: {
    type: "object";
    properties: Record<string, { type: string; description?: string; enum?: string[] }>;
    required?: string[];
  };
};

const MODEL = process.env.GEMINI_MODEL || "gemini-3.6-flash";

async function callGemini(contents: GeminiContent[], tools: ToolDeclaration[], systemText: string) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error("GEMINI_API_KEY is not set");

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemText }] },
        contents,
        tools: tools.length ? [{ functionDeclarations: tools }] : undefined,
        generationConfig: { temperature: 0.4 },
      }),
    }
  );

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`Gemini API error ${res.status}: ${body.slice(0, 500)}`);
  }
  return res.json();
}

/**
 * Runs the chat loop: sends the conversation + tool definitions to Gemini, and any time
 * it asks to call a tool, executes it locally and feeds the result back — up to a small
 * round cap so a confused model can't loop forever — until it returns plain text.
 */
export async function chatWithTools(
  history: GeminiContent[],
  tools: ToolDeclaration[],
  executeTool: (name: string, args: Record<string, unknown>) => Promise<Record<string, unknown>>,
  systemText: string,
  maxRounds = 4
): Promise<{ reply: string; toolCalls: { name: string; args: unknown }[] }> {
  const contents = [...history];
  const toolCalls: { name: string; args: unknown }[] = [];

  for (let round = 0; round < maxRounds; round++) {
    const data = await callGemini(contents, tools, systemText);
    const candidate = data?.candidates?.[0];
    const parts: GeminiPart[] = candidate?.content?.parts ?? [];

    const functionCallPart = parts.find((p): p is Extract<GeminiPart, { functionCall: any }> => "functionCall" in p);

    if (!functionCallPart) {
      const text = parts.map((p) => ("text" in p ? p.text : "")).join("").trim();
      return { reply: text || "I didn't get a response back — try asking again.", toolCalls };
    }

    const { name, args } = functionCallPart.functionCall;
    toolCalls.push({ name, args });

    let result: Record<string, unknown>;
    try {
      result = await executeTool(name, args || {});
    } catch (err: any) {
      result = { error: err?.message || "Tool call failed" };
    }

    contents.push({ role: "model", parts: [functionCallPart] });
    contents.push({ role: "user", parts: [{ functionResponse: { name, response: result } }] });
  }

  return { reply: "That took more steps than I could finish in one go — try narrowing the question.", toolCalls };
}
