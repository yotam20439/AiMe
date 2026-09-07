import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });

  const household = await prisma.household.findUnique({
    where: { id: (session.user as any).householdId },
    include: { members: { select: { id: true, name: true, email: true, role: true } } },
  });
  return NextResponse.json({ household });
}
