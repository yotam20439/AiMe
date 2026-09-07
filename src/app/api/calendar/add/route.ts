import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { getCalendarClient } from "@/lib/gmail";

// This route only ever runs when a person clicks "Add to calendar" in the UI —
// there is no code path anywhere that calls it without that click.
export async function POST(req: Request) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const userId = (session.user as any).id;

  const { title, start, end } = await req.json().catch(() => ({}));
  if (!title || !start || !end) {
    return NextResponse.json({ error: "title, start, and end are required" }, { status: 400 });
  }

  const integration = await prisma.integration.findUnique({
    where: { userId_provider: { userId, provider: "google" } },
  });
  if (!integration) return NextResponse.json({ error: "Google isn't connected" }, { status: 400 });

  const calendar = await getCalendarClient(integration);
  const event = await calendar.events.insert({
    calendarId: "primary",
    requestBody: { summary: title, start: { dateTime: start }, end: { dateTime: end } },
  });

  await prisma.activityEvent.create({
    data: { userId, text: `Added "${title}" to your calendar.`, kind: "calendar" },
  });

  return NextResponse.json({ ok: true, eventId: event.data.id });
}
