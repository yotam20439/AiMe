import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { chatWithTools, type GeminiContent } from "@/lib/gemini";
import { ASSISTANT_TOOLS, ASSISTANT_SYSTEM_PROMPT, makeToolExecutor } from "@/lib/assistant-tools";

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });

  const messages = await prisma.chatMessage.findMany({
    where: { userId: (session.user as any).id },
    orderBy: { createdAt: "asc" },
    take: 100,
  });
  return NextResponse.json({ messages });
}

export async function POST(req: Request) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const userId = (session.user as any).id;

  const { message } = await req.json().catch(() => ({}));
  if (!message || typeof message !== "string" || !message.trim()) {
    return NextResponse.json({ error: "message is required" }, { status: 400 });
  }

  await prisma.chatMessage.create({ data: { userId, role: "user", content: message } });

  // Recent history gives Gemini context without resending the whole conversation forever.
  const recent = await prisma.chatMessage.findMany({
    where: { userId }, orderBy: { createdAt: "desc" }, take: 20,
  });
  const history: GeminiContent[] = recent.reverse().map((m) => ({
    role: m.role === "user" ? "user" : "model",
    parts: [{ text: m.content }],
  }));

  let reply: string;
  try {
    const result = await chatWithTools(history, ASSISTANT_TOOLS, makeToolExecutor(userId), ASSISTANT_SYSTEM_PROMPT);
    reply = result.reply;
  } catch (err: any) {
    reply = `Something went wrong talking to Gemini: ${err?.message || "unknown error"}`;
  }

  await prisma.chatMessage.create({ data: { userId, role: "model", content: reply } });
  return NextResponse.json({ reply });
}
