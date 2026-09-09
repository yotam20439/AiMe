import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { getGmailClient, listCandidateMessages } from "@/lib/gmail";
import { extractTask } from "@/lib/extract";

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
      const gmail = await getGmailClient(integration);
      const messages = await listCandidateMessages(gmail);
      matchedCount += messages.length;

      for (const msg of messages) {
        // Already turned into a task on a previous run — skip without spending an AI call.
        const existing = await prisma.task.findUnique({
          where: { userId_sourceRef: { userId: integration.userId, sourceRef: msg.id } },
        });
        if (existing) { alreadyTrackedCount++; continue; }

        const text = `From: ${msg.from}\nSubject: ${msg.subject}\n\n${msg.snippet}`;
        const extracted = await extractTask("Gmail", text);
        if (!extracted?.isActionable) {
          notActionableCount++;
          if (notActionableSample.length < 5) notActionableSample.push({ subject: msg.subject, from: msg.from });
          continue;
        }

        const user = await prisma.user.findUnique({ where: { id: integration.userId } });
        if (!user) continue;

        await prisma.task.create({
          data: {
            userId: user.id,
            householdId: user.householdId,
            sourceRef: msg.id,
            source: "gmail",
            title: extracted.title || msg.subject,
            type: extracted.type || "task",
            category: extracted.category || "personal",
            priority: extracted.priority || "normal",
            amount: extracted.amount ?? null,
            currency: extracted.currency ?? null,
            due: extracted.dueDate ? new Date(extracted.dueDate) : null,
            aiSummary: extracted.whySummary || null,
            why: `Found in an email from ${msg.from}, subject "${msg.subject}".`,
          },
        });
        await prisma.activityEvent.create({
          data: { userId: user.id, text: `Found "${extracted.title || msg.subject}" in Gmail.`, kind: "tasks" },
        });
        created++;
      }

      await prisma.integration.update({ where: { id: integration.id }, data: { lastSyncAt: new Date() } });
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
    notActionableSample, // subjects the AI looked at but decided weren't worth a task — useful for tuning
  });
}
