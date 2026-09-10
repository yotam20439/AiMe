import { prisma } from "./db";
import { getGmailClient, listCandidateMessages } from "./gmail";
import { extractTask } from "./extract";
import type { Integration } from "@prisma/client";

export type ScanResult = {
  candidateMessagesMatched: number;
  alreadyTracked: number;
  judgedNotActionable: number;
  tasksCreated: number;
  createdTitles: string[];
  notActionableSample: { subject: string; from: string }[];
};

// Scans one person's connected Gmail for bills/important messages and creates tasks
// for whatever's actually actionable. This is the single place sourceRef gets set —
// always the real Gmail message id, always correct, because it's set here in code
// rather than trusted to an AI's memory across several tool-call steps.
export async function scanGmailForIntegration(integration: Integration): Promise<ScanResult> {
  let created = 0;
  let matchedCount = 0;
  let notActionableCount = 0;
  let alreadyTrackedCount = 0;
  const createdTitles: string[] = [];
  const notActionableSample: { subject: string; from: string }[] = [];

  const gmail = await getGmailClient(integration);
  const messages = await listCandidateMessages(gmail);
  matchedCount += messages.length;

  for (const msg of messages) {
    const existing = await prisma.task.findUnique({
      where: { userId_sourceRef: { userId: integration.userId, sourceRef: msg.id } },
    });
    if (existing) { alreadyTrackedCount++; continue; }

    const text = `From: ${msg.from}\nSubject: ${msg.subject}\n\n${msg.bodyText || msg.snippet}`;
    const extracted = await extractTask("Gmail", text, msg.links);
    if (!extracted?.isActionable) {
      notActionableCount++;
      if (notActionableSample.length < 5) notActionableSample.push({ subject: msg.subject, from: msg.from });
      continue;
    }

    const user = await prisma.user.findUnique({ where: { id: integration.userId } });
    if (!user) continue;

    const title = extracted.title || msg.subject;
    await prisma.task.create({
      data: {
        userId: user.id,
        householdId: user.householdId,
        sourceRef: msg.id,
        source: "gmail",
        title,
        type: extracted.type || "task",
        category: extracted.category || "personal",
        priority: extracted.priority || "normal",
        amount: extracted.amount ?? null,
        currency: extracted.currency ?? null,
        due: extracted.dueDate ? new Date(extracted.dueDate) : null,
        actionUrl: extracted.actionUrl ?? null,
        emailDate: msg.date && !isNaN(new Date(msg.date).getTime()) ? new Date(msg.date) : null,
        aiSummary: extracted.whySummary || null,
        why: `Found in an email from ${msg.from}, subject "${msg.subject}".`,
      },
    });
    await prisma.activityEvent.create({
      data: { userId: user.id, text: `Found "${title}" in Gmail.`, kind: "tasks" },
    });
    created++;
    createdTitles.push(title);
  }

  await prisma.integration.update({ where: { id: integration.id }, data: { lastSyncAt: new Date() } });

  return {
    candidateMessagesMatched: matchedCount,
    alreadyTracked: alreadyTrackedCount,
    judgedNotActionable: notActionableCount,
    tasksCreated: created,
    createdTitles,
    notActionableSample,
  };
}
