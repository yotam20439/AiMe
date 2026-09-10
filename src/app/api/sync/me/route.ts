import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { scanGmailForIntegration } from "@/lib/scan";

// Called automatically when Today loads. Reuses the exact same reliable pipeline
// as the scheduled cron job, just scoped to one person and triggered by a page
// visit instead of a timer.
const COOLDOWN_MS = 5 * 60 * 1000;

export async function POST() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const userId = (session.user as any).id;

  const integration = await prisma.integration.findUnique({
    where: { userId_provider: { userId, provider: "google" } },
  });
  if (!integration || integration.status !== "connected") {
    return NextResponse.json({ skipped: true, reason: "not-connected" });
  }

  if (integration.lastSyncAt && Date.now() - integration.lastSyncAt.getTime() < COOLDOWN_MS) {
    return NextResponse.json({ skipped: true, reason: "cooldown", lastSyncAt: integration.lastSyncAt });
  }

  try {
    const result = await scanGmailForIntegration(integration);
    return NextResponse.json({ skipped: false, ...result });
  } catch (err: any) {
    console.error("Auto-sync on load failed:", err);
    return NextResponse.json({ error: err?.message || "Sync failed" }, { status: 500 });
  }
}
