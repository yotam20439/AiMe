import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";

export async function POST(req: Request) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });

  const { level } = await req.json().catch(() => ({}));
  if (!["gentle", "balanced", "proactive"].includes(level)) {
    return NextResponse.json({ error: "Invalid level" }, { status: 400 });
  }

  await prisma.user.update({ where: { id: (session.user as any).id }, data: { proactivity: level } });
  return NextResponse.json({ ok: true });
}
