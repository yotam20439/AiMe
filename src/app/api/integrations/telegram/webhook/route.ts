import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { extractTask } from "@/lib/extract";

async function reply(chatId: number | string, text: string) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) return;
  await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, text }),
  }).catch(() => {});
}

export async function POST(req: Request) {
  // Telegram sends this header when a secret_token was set on setWebhook (see README).
  // Anyone else hitting this URL is rejected before we read the body.
  const secret = req.headers.get("x-telegram-bot-api-secret-token");
  if (process.env.TELEGRAM_WEBHOOK_SECRET && secret !== process.env.TELEGRAM_WEBHOOK_SECRET) {
    return NextResponse.json({ ok: false }, { status: 401 });
  }

  const update = await req.json().catch(() => null);
  const message = update?.message;
  if (!message?.chat?.id || typeof message.text !== "string") {
    return NextResponse.json({ ok: true }); // ignore non-text updates (stickers, edits, etc.)
  }

  const chatId: number = message.chat.id;
  const text: string = message.text.trim();

  // Step 1: linking. "/start <code>" arrives the moment someone taps the deep link.
  if (text.startsWith("/start")) {
    const code = text.split(" ")[1];
    const pending = code
      ? await prisma.pendingLink.findUnique({ where: { code } })
      : null;

    if (!pending || pending.provider !== "telegram" || pending.expiresAt < new Date()) {
      await reply(chatId, "That link has expired. Go back to AiMe and tap Connect Telegram again.");
      return NextResponse.json({ ok: true });
    }

    await prisma.integration.upsert({
      where: { userId_provider: { userId: pending.userId, provider: "telegram" } },
      create: { userId: pending.userId, provider: "telegram", status: "connected", externalId: String(chatId) },
      update: { status: "connected", externalId: String(chatId) },
    });
    await prisma.pendingLink.delete({ where: { id: pending.id } });
    await prisma.activityEvent.create({
      data: { userId: pending.userId, text: "Connected Telegram.", kind: "automations" },
    });
    await reply(chatId, "Connected! Message me things like \u201cremind me to call David tomorrow\u201d and I'll turn them into tasks.");
    return NextResponse.json({ ok: true });
  }

  // Step 2: ordinary message from an already-linked chat — try to extract a task.
  const integration = await prisma.integration.findFirst({
    where: { provider: "telegram", externalId: String(chatId), status: "connected" },
  });
  if (!integration) {
    await reply(chatId, "I don't recognize this chat yet. Connect Telegram from AiMe first.");
    return NextResponse.json({ ok: true });
  }

  const sourceRef = `telegram:${chatId}:${message.message_id}`;
  const extracted = await extractTask("Telegram message", text).catch(() => null);

  if (!extracted?.isActionable) {
    await reply(chatId, "Noted — nothing for me to track there.");
    return NextResponse.json({ ok: true });
  }

  const user = await prisma.user.findUnique({ where: { id: integration.userId } });
  if (!user) return NextResponse.json({ ok: true });

  await prisma.task.upsert({
    where: { userId_sourceRef: { userId: user.id, sourceRef } },
    create: {
      userId: user.id,
      householdId: user.householdId,
      sourceRef,
      source: "telegram",
      title: extracted.title || text.slice(0, 60),
      type: extracted.type || "task",
      category: extracted.category || "personal",
      priority: extracted.priority || "normal",
      due: extracted.dueDate ? new Date(extracted.dueDate) : null,
      aiSummary: extracted.whySummary || null,
      why: `Detected in a Telegram message: \u201c${text.slice(0, 140)}\u201d`,
    },
    update: {},
  });

  await prisma.activityEvent.create({
    data: { userId: user.id, text: `Detected a reminder in Telegram.`, kind: "messages" },
  });

  await reply(chatId, `Got it — added \u201c${extracted.title || text.slice(0, 60)}\u201d to your tasks.`);
  return NextResponse.json({ ok: true });
}
