import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { google } from "googleapis";
import { authOptions } from "@/lib/auth";
import { createGoogleOAuthClient } from "@/lib/google";
import { encrypt } from "@/lib/crypto";
import { prisma } from "@/lib/db";

export async function GET(req: Request) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.redirect(new URL("/login", process.env.NEXTAUTH_URL));

  const { searchParams } = new URL(req.url);
  const code = searchParams.get("code");
  const state = searchParams.get("state");
  const userId = (session.user as any).id;

  // state should match the signed-in user who started the flow; if it doesn't,
  // refuse rather than silently attaching Google tokens to the wrong account.
  if (!code || state !== userId) {
    return NextResponse.redirect(new URL("/onboarding?error=google", process.env.NEXTAUTH_URL));
  }

  try {
    const oauth2Client = createGoogleOAuthClient();
    const { tokens } = await oauth2Client.getToken(code);

    oauth2Client.setCredentials(tokens);
    const oauth2 = google.oauth2({ version: "v2", auth: oauth2Client });
    const info = await oauth2.userinfo.get().catch(() => null);

    await prisma.integration.upsert({
      where: { userId_provider: { userId, provider: "google" } },
      create: {
        userId,
        provider: "google",
        accountLabel: info?.data?.email ?? "Google account",
        accessTokenEnc: tokens.access_token ? encrypt(tokens.access_token) : null,
        refreshTokenEnc: tokens.refresh_token ? encrypt(tokens.refresh_token) : null,
        scope: tokens.scope ?? null,
        expiresAt: tokens.expiry_date ? new Date(tokens.expiry_date) : null,
        status: "connected",
      },
      update: {
        accountLabel: info?.data?.email ?? "Google account",
        accessTokenEnc: tokens.access_token ? encrypt(tokens.access_token) : undefined,
        // Google only sends a refresh_token on the first consent, or when prompt=consent is forced
        // (which /connect always does) — so it's safe to overwrite when present.
        refreshTokenEnc: tokens.refresh_token ? encrypt(tokens.refresh_token) : undefined,
        scope: tokens.scope ?? null,
        expiresAt: tokens.expiry_date ? new Date(tokens.expiry_date) : null,
        status: "connected",
      },
    });

    await prisma.activityEvent.create({
      data: { userId, text: `Connected Gmail, Calendar and Drive (${info?.data?.email ?? "Google"}).`, kind: "automations" },
    });

    return NextResponse.redirect(new URL("/onboarding?connected=google", process.env.NEXTAUTH_URL));
  } catch (err: any) {
    // Most likely cause: ENCRYPTION_KEY (or another required env var) isn't set on Vercel.
    console.error("Google callback failed:", err);
    const url = new URL("/onboarding", process.env.NEXTAUTH_URL);
    url.searchParams.set("error", "google");
    url.searchParams.set("detail", (err?.message || "unknown error").slice(0, 200));
    return NextResponse.redirect(url);
  }
}
