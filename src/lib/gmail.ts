import { google, gmail_v1 } from "googleapis";
import { createGoogleOAuthClient } from "./google";
import { decrypt, encrypt } from "./crypto";
import { prisma } from "./db";
import type { Integration } from "@prisma/client";

// Builds an authenticated Gmail client for one person's connection, and makes
// sure that if Google hands back a refreshed access token mid-request, the new
// (still encrypted) token is written back to the database immediately.
export async function getGmailClient(integration: Integration): Promise<gmail_v1.Gmail> {
  const oauth2Client = createGoogleOAuthClient();
  oauth2Client.setCredentials({
    access_token: integration.accessTokenEnc ? decrypt(integration.accessTokenEnc) : undefined,
    refresh_token: integration.refreshTokenEnc ? decrypt(integration.refreshTokenEnc) : undefined,
    expiry_date: integration.expiresAt ? integration.expiresAt.getTime() : undefined,
  });

  oauth2Client.on("tokens", async (tokens) => {
    const data: Record<string, unknown> = {};
    if (tokens.access_token) data.accessTokenEnc = encrypt(tokens.access_token);
    if (tokens.refresh_token) data.refreshTokenEnc = encrypt(tokens.refresh_token);
    if (tokens.expiry_date) data.expiresAt = new Date(tokens.expiry_date);
    if (Object.keys(data).length) {
      await prisma.integration.update({ where: { id: integration.id }, data }).catch(() => {});
    }
  });

  return google.gmail({ version: "v1", auth: oauth2Client });
}

export async function getCalendarClient(integration: Integration) {
  const oauth2Client = createGoogleOAuthClient();
  oauth2Client.setCredentials({
    access_token: integration.accessTokenEnc ? decrypt(integration.accessTokenEnc) : undefined,
    refresh_token: integration.refreshTokenEnc ? decrypt(integration.refreshTokenEnc) : undefined,
  });
  return google.calendar({ version: "v3", auth: oauth2Client });
}

// A narrow, cheap-to-run keyword prefilter so we only spend an AI call on
// messages that plausibly contain a bill, appointment, or deadline — not on
// every newsletter in the inbox.
const CANDIDATE_QUERY =
  'newer_than:2d (bill OR invoice OR payment OR due OR appointment OR confirm OR receipt OR "sign" OR deadline) -category:promotions';

export async function listCandidateMessages(gmail: gmail_v1.Gmail, max = 15) {
  const list = await gmail.users.messages.list({
    userId: "me",
    q: CANDIDATE_QUERY,
    maxResults: max,
  });
  const ids = list.data.messages ?? [];
  const messages = await Promise.all(
    ids.map(async (m) => {
      const full = await gmail.users.messages.get({
        userId: "me",
        id: m.id!,
        format: "metadata",
        metadataHeaders: ["Subject", "From", "Date"],
      });
      const headers = full.data.payload?.headers ?? [];
      const get = (name: string) => headers.find((h) => h.name === name)?.value ?? "";
      return {
        id: m.id!,
        subject: get("Subject"),
        from: get("From"),
        date: get("Date"),
        snippet: full.data.snippet ?? "",
      };
    })
  );
  return messages;
}
