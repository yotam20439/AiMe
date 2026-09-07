import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { encrypt } from "@/lib/crypto";

export async function GET(req: Request) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.redirect(new URL("/login", process.env.NEXTAUTH_URL));

  const { searchParams } = new URL(req.url);
  const code = searchParams.get("code");
  const state = searchParams.get("state");
  const userId = (session.user as any).id;
  if (!code || state !== userId) {
    return NextResponse.redirect(new URL("/onboarding?error=notion", process.env.NEXTAUTH_URL));
  }

  const redirectUri = `${process.env.NEXTAUTH_URL}/api/integrations/notion/callback`;
  const basic = Buffer.from(`${process.env.NOTION_CLIENT_ID}:${process.env.NOTION_CLIENT_SECRET}`).toString("base64");

  const tokenRes = await fetch("https://api.notion.com/v1/oauth/token", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Basic ${basic}` },
    body: JSON.stringify({ grant_type: "authorization_code", code, redirect_uri: redirectUri }),
  });
  const data = await tokenRes.json();

  if (!tokenRes.ok) {
    return NextResponse.redirect(new URL("/onboarding?error=notion", process.env.NEXTAUTH_URL));
  }

  await prisma.integration.upsert({
    where: { userId_provider: { userId, provider: "notion" } },
    create: {
      userId,
      provider: "notion",
      accountLabel: data.workspace_name ?? "Notion workspace",
      externalId: data.workspace_id ?? null,
      accessTokenEnc: encrypt(data.access_token),
      status: "connected",
    },
    update: {
      accountLabel: data.workspace_name ?? "Notion workspace",
      externalId: data.workspace_id ?? null,
      accessTokenEnc: encrypt(data.access_token),
      status: "connected",
    },
  });

  await prisma.activityEvent.create({
    data: { userId, text: `Connected Notion (${data.workspace_name ?? "workspace"}).`, kind: "automations" },
  });

  return NextResponse.redirect(new URL("/onboarding?connected=notion", process.env.NEXTAUTH_URL));
}
