import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.redirect(new URL("/login", process.env.NEXTAUTH_URL));

  const redirectUri = `${process.env.NEXTAUTH_URL}/api/integrations/slack/callback`;
  const params = new URLSearchParams({
    client_id: process.env.SLACK_CLIENT_ID || "",
    // channels:history/groups:history let AiMe later read threads addressed to you;
    // chat:write is only used for drafts you explicitly send, never silently.
    scope: "channels:history,groups:history,chat:write,users:read",
    redirect_uri: redirectUri,
    state: (session.user as any).id,
  });

  return NextResponse.redirect(`https://slack.com/oauth/v2/authorize?${params.toString()}`);
}
