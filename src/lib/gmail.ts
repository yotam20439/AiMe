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
  '(bill OR invoice OR payment OR due OR appointment OR confirm OR receipt OR "sign" OR deadline OR ' +
  'invite OR invitation OR RSVP OR reminder OR ' +
  'חשבונית OR חשבון OR תשלום OR לתשלום OR תור OR פגישה OR קבלה OR אישור OR חתימה OR "מועד אחרון" OR הזמנה)';

export async function listCandidateMessages(gmail: gmail_v1.Gmail, max = 30) {
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

// The label a dismissed task's source email gets moved into. Gmail doesn't have real
// folders — moving a message "out of the inbox" means removing the INBOX label and
// adding this one, which Gmail's UI then displays as a folder-like label.
export const DISMISSED_LABEL_NAME = "AiMe/Dismissed";

async function getOrCreateLabel(gmail: gmail_v1.Gmail, name: string): Promise<string> {
  const list = await gmail.users.labels.list({ userId: "me" });
  const existing = list.data.labels?.find((l) => l.name === name);
  if (existing?.id) return existing.id;

  const created = await gmail.users.labels.create({
    userId: "me",
    requestBody: { name, labelListVisibility: "labelShow", messageListVisibility: "show" },
  });
  return created.data.id!;
}

export async function moveMessageOutOfInbox(gmail: gmail_v1.Gmail, messageId: string, labelName = DISMISSED_LABEL_NAME) {
  const labelId = await getOrCreateLabel(gmail, labelName);
  await gmail.users.messages.modify({
    userId: "me",
    id: messageId,
    requestBody: { removeLabelIds: ["INBOX"], addLabelIds: [labelId] },
  });
}
