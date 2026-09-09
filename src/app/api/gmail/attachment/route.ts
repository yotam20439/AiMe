import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { getGmailClient, getAttachmentBytes } from "@/lib/gmail";

export async function GET(req: Request) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const userId = (session.user as any).id;

  const { searchParams } = new URL(req.url);
  const messageId = searchParams.get("messageId");
  const attachmentId = searchParams.get("attachmentId");
  const filename = (searchParams.get("filename") || "attachment").replace(/["\r\n]/g, "");
  const mimeType = searchParams.get("mimeType") || "application/octet-stream";

  if (!messageId || !attachmentId) {
    return NextResponse.json({ error: "messageId and attachmentId are required" }, { status: 400 });
  }

  const integration = await prisma.integration.findUnique({
    where: { userId_provider: { userId, provider: "google" } },
  });
  if (!integration) return NextResponse.json({ error: "Google isn't connected" }, { status: 400 });

  try {
    const gmail = await getGmailClient(integration);
    const bytes = await getAttachmentBytes(gmail, messageId, attachmentId);
    return new NextResponse(new Uint8Array(bytes), {
      headers: {
        "content-type": mimeType,
        "content-disposition": `inline; filename="${filename}"`,
        "content-length": String(bytes.length),
      },
    });
  } catch (err) {
    console.error("Failed to fetch attachment:", err);
    return NextResponse.json({ error: "Couldn't fetch the attachment — try reconnecting Google." }, { status: 500 });
  }
}
