import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { scanGmailForIntegration } from "@/lib/scan";

export const dynamic = "force-dynamic";

// Registered in vercel.json to run on a schedule. Vercel signs cron requests with
// an Authorization header matching CRON_SECRET — anyone else calling this gets 401.
export async function GET(req: Request) {
  const auth = req.headers.get("authorization");
  if (auth !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const integrations = await prisma.integration.findMany({
    where: { provider: "google", status: "connected" },
  });

  let created = 0;
  let matchedCount = 0;
  let notActionableCount = 0;
  let alreadyTrackedCount = 0;
  const notActionableSample: { subject: string; from: string }[] = [];

  for (const integration of integrations) {
    try {
      const result = await scanGmailForIntegration(integration);
      created += result.tasksCreated;
      matchedCount += result.candidateMessagesMatched;
      notActionableCount += result.judgedNotActionable;
      alreadyTrackedCount += result.alreadyTracked;
      notActionableSample.push(...result.notActionableSample.slice(0, Math.max(0, 5 - notActionableSample.length)));
    } catch (err) {
      console.error(`Sync failed for integration ${integration.id}`, err);
      await prisma.integration.update({ where: { id: integration.id }, data: { status: "error" } }).catch(() => {});
    }
  }

  return NextResponse.json({
    ok: true,
    checked: integrations.length,
    candidateMessagesMatched: matchedCount,
    alreadyTracked: alreadyTrackedCount,
    judgedNotActionable: notActionableCount,
    tasksCreated: created,
    notActionableSample,
  });
}
