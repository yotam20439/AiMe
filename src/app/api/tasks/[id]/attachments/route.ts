import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { getGmailClient, listAttachments } from "@/lib/gmail";

export async function GET(_req: Request, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const userId = (session.user as any).id;

  const task = await prisma.task.findUnique({ where: { id: params.id } });
  if (!task || task.userId !== userId) return NextResponse.json({ error: "Not found" }, { status: 404 });
  if (task.source !== "gmail" || !task.sourceRef) return NextResponse.json({ attachments: [] });

  const integration = await prisma.integration.findUnique({
    where: { userId_provider: { userId, provider: "google" } },
  });
  if (!integration) return NextResponse.json({ attachments: [] });

  try {
    const gmail = await getGmailClient(integration);
    const attachments = await listAttachments(gmail, task.sourceRef);
    return NextResponse.json({ attachments });
  } catch (err) {
    console.error("Failed to list attachments:", err);
    return NextResponse.json({ attachments: [] });
  }
}
