import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";

export const dynamic = "force-dynamic";

// Protected the same way as the cron endpoint. Safe to run more than once — it only
// ever touches rows still carrying the old bug's signature (source:'chat' with a
// sourceRef that isn't one of chat's own synthetic keys).
export async function GET(req: Request) {
  const auth = req.headers.get("authorization");
  if (auth !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const result = await prisma.task.updateMany({
    where: {
      source: "chat",
      sourceRef: { not: null },
      NOT: { sourceRef: { startsWith: "chat:" } },
    },
    data: { source: "gmail" },
  });

  return NextResponse.json({ ok: true, fixed: result.count });
}
