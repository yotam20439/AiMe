import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { getGmailClient, moveMessageOutOfInbox } from "@/lib/gmail";

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const userId = (session.user as any).id;
  const householdId = (session.user as any).householdId;

  const tasks = await prisma.task.findMany({
    where: {
      OR: [{ userId }, { householdId, visibility: "household" }],
      status: { not: "dismissed" },
    },
    orderBy: [{ status: "asc" }, { due: "asc" }],
    include: { user: { select: { name: true } } },
  });

  return NextResponse.json({ tasks });
}

// Both outcomes get their own label, so wherever a task ends up, its source email
// leaves the inbox and lands somewhere clearly named for reference. Only genuinely
// still-open tasks' emails stay in the inbox.
const LABEL_FOR_STATUS: Record<string, string> = {
  completed: "AiMe/Completed",
  dismissed: "AiMe/Dismissed",
};

export async function PATCH(req: Request) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const userId = (session.user as any).id;

  const { id, status, visibility } = await req.json().catch(() => ({}));
  const task = await prisma.task.findUnique({ where: { id } });
  if (!task || task.userId !== userId) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const updated = await prisma.task.update({
    where: { id },
    data: {
      ...(status ? { status } : {}),
      ...(visibility ? { visibility } : {}),
    },
  });

  // A sourceRef starting with "chat:" is a synthetic key for a task that was never
  // actually tied to a real email — there's nothing in Gmail to move, so don't try.
  const hasRealEmail = task.source === "gmail" && !!task.sourceRef && !task.sourceRef.startsWith("chat:");
  const label = status ? LABEL_FOR_STATUS[status] : undefined;

  let inboxMoveError: string | null = null;
  if (label && hasRealEmail) {
    try {
      const integration = await prisma.integration.findUnique({
        where: { userId_provider: { userId, provider: "google" } },
      });
      if (integration) {
        const gmail = await getGmailClient(integration);
        await moveMessageOutOfInbox(gmail, task.sourceRef as string, label);
        await prisma.activityEvent.create({
          data: { userId, text: `Moved the source email for "${task.title}" to ${label}.`, kind: "automations" },
        });
      }
    } catch (err: any) {
      console.error("Failed to move task's source email:", err);
      inboxMoveError = "Saved, but couldn't move the email in Gmail — try reconnecting Google in Connections.";
    }
  } else if (status === "completed") {
    await prisma.activityEvent.create({
      data: { userId, text: `Completed "${task.title}".`, kind: "tasks" },
    });
  }

  return NextResponse.json({ task: updated, inboxMoveError });
}
