import { google } from "googleapis";

// Read-only by default, on purpose. calendar.events is included only so a user
// can click "Add to calendar" on a AiMe suggestion — that still requires their
// explicit click (see api/calendar/add), never a silent write.
export const GOOGLE_SCOPES = [
  "https://www.googleapis.com/auth/gmail.readonly",
  "https://www.googleapis.com/auth/calendar.readonly",
  "https://www.googleapis.com/auth/calendar.events",
  "https://www.googleapis.com/auth/drive.readonly",
  "https://www.googleapis.com/auth/userinfo.email",
];

export function getRedirectUri() {
  return `${process.env.NEXTAUTH_URL}/api/integrations/google/callback`;
}

export function createGoogleOAuthClient() {
  return new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    getRedirectUri()
  );
}
