import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });

  const integrations = await prisma.integration.findMany({
    where: { userId: (session.user as any).id },
    select: { provider: true, status: true, accountLabel: true, lastSyncAt: true },
  });

  return NextResponse.json({ integrations });
}
