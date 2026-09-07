import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { randomCode } from "@/lib/crypto";

// Telegram has no concept of OAuth for this: instead, we hand the browser a short
// code and a deep link. The person taps it, Telegram opens a chat with the bot and
// sends "/start <code>" automatically, and the webhook (see ../webhook) matches
// that code back to this signed-in user. No phone number or contact list is ever read.
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const userId = (session.user as any).id;

  const code = randomCode(6);
  await prisma.pendingLink.create({
    data: { code, userId, provider: "telegram", expiresAt: new Date(Date.now() + 15 * 60 * 1000) },
  });

  const username = process.env.TELEGRAM_BOT_USERNAME;
  return NextResponse.json({
    code,
    deepLink: username ? `https://t.me/${username}?start=${code}` : null,
  });
}
