import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });

  const integration = await prisma.integration.findUnique({
    where: { userId_provider: { userId: (session.user as any).id, provider: "telegram" } },
  });

  return NextResponse.json({ connected: integration?.status === "connected" });
}
