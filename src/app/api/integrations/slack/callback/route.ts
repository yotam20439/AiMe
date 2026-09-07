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
    return NextResponse.redirect(new URL("/onboarding?error=slack", process.env.NEXTAUTH_URL));
  }

  const redirectUri = `${process.env.NEXTAUTH_URL}/api/integrations/slack/callback`;
  const tokenRes = await fetch("https://slack.com/api/oauth.v2.access", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: process.env.SLACK_CLIENT_ID || "",
      client_secret: process.env.SLACK_CLIENT_SECRET || "",
      code,
      redirect_uri: redirectUri,
    }),
  });
  const data = await tokenRes.json();

  if (!data.ok) {
    return NextResponse.redirect(new URL("/onboarding?error=slack", process.env.NEXTAUTH_URL));
  }

  await prisma.integration.upsert({
    where: { userId_provider: { userId, provider: "slack" } },
    create: {
      userId,
      provider: "slack",
      accountLabel: data.team?.name ?? "Slack workspace",
      externalId: data.team?.id ?? null,
      accessTokenEnc: encrypt(data.access_token),
      scope: data.scope ?? null,
      status: "connected",
    },
    update: {
      accountLabel: data.team?.name ?? "Slack workspace",
      externalId: data.team?.id ?? null,
      accessTokenEnc: encrypt(data.access_token),
      scope: data.scope ?? null,
      status: "connected",
    },
  });

  await prisma.activityEvent.create({
    data: { userId, text: `Connected Slack (${data.team?.name ?? "workspace"}).`, kind: "automations" },
  });

  return NextResponse.redirect(new URL("/onboarding?connected=slack", process.env.NEXTAUTH_URL));
}
