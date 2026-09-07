import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";

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

  if (status === "completed") {
    await prisma.activityEvent.create({
      data: { userId, text: `Completed "${task.title}".`, kind: "tasks" },
    });
  }

  return NextResponse.json({ task: updated });
}
