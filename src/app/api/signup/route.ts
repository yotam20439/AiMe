import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { hashPassword } from "@/lib/password";
import { randomCode } from "@/lib/crypto";

export async function POST(req: Request) {
  const body = await req.json().catch(() => null);
  const { name, email, password, mode, householdName, inviteCode } = body ?? {};

  if (!name || !email || !password || password.length < 8) {
    return NextResponse.json(
      { error: "Name, email, and a password of at least 8 characters are required." },
      { status: 400 }
    );
  }

  const normalizedEmail = String(email).toLowerCase().trim();
  const existing = await prisma.user.findUnique({ where: { email: normalizedEmail } });
  if (existing) {
    return NextResponse.json({ error: "An account already exists with that email." }, { status: 409 });
  }

  const passwordHash = await hashPassword(password);

  if (mode === "join") {
    const household = await prisma.household.findUnique({ where: { inviteCode: String(inviteCode || "").trim() } });
    if (!household) {
      return NextResponse.json({ error: "That invite code doesn't match a household." }, { status: 404 });
    }
    const user = await prisma.user.create({
      data: { name, email: normalizedEmail, passwordHash, householdId: household.id, role: "member" },
    });
    return NextResponse.json({ ok: true, userId: user.id });
  }

  // mode === "create": this person becomes the household's first member/owner.
  const household = await prisma.household.create({
    data: { name: householdName || `${name}'s household`, inviteCode: randomCode(4) },
  });
  const user = await prisma.user.create({
    data: { name, email: normalizedEmail, passwordHash, householdId: household.id, role: "owner" },
  });
  return NextResponse.json({ ok: true, userId: user.id, inviteCode: household.inviteCode });
}
