import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { createGoogleOAuthClient, GOOGLE_SCOPES } from "@/lib/google";

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.redirect(new URL("/login", process.env.NEXTAUTH_URL));

  const oauth2Client = createGoogleOAuthClient();
  const url = oauth2Client.generateAuthUrl({
    access_type: "offline", // needed to receive a refresh token
    prompt: "consent", // forces a refresh token even on repeat connects
    scope: GOOGLE_SCOPES,
    state: (session.user as any).id, // matched back up in the callback
  });

  return NextResponse.redirect(url);
}
