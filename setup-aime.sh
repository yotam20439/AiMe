#!/usr/bin/env bash
set -e
echo "Creating AiMe project files..."

cat > ".env.example" << 'AIME_HEREDOC_EOF_9f2c'
# --- Database ---
# Any Postgres works (Neon, Vercel Postgres, Supabase). Free tier is fine for household scale.
DATABASE_URL="postgresql://user:password@host:5432/nudge"

# --- Auth (this app's own login, separate from any integration) ---
# Generate with: openssl rand -base64 32
NEXTAUTH_SECRET=""
NEXTAUTH_URL="http://localhost:3000"

# Encrypts every OAuth token before it touches the database.
# Generate with: openssl rand -base64 32
ENCRYPTION_KEY=""

# Protects the cron endpoint from being called by anyone but Vercel/you.
# Generate with: openssl rand -base64 32
CRON_SECRET=""

# --- Google (Gmail, Calendar, Drive) ---
# console.cloud.google.com -> new project -> OAuth consent screen -> "Testing" mode
# -> add each family member's Gmail address as a test user (no Google review needed, up to 100 users)
# -> Credentials -> OAuth client ID -> Web application
# -> Authorized redirect URI: {NEXTAUTH_URL}/api/integrations/google/callback
GOOGLE_CLIENT_ID=""
GOOGLE_CLIENT_SECRET=""

# --- Telegram (stands in for WhatsApp — there is no personal-WhatsApp read API) ---
# Message @BotFather on Telegram -> /newbot -> copy the token and the bot's @username
TELEGRAM_BOT_TOKEN=""
TELEGRAM_BOT_USERNAME=""
# Any random string. Passed to Telegram when registering the webhook (see README)
# so the webhook route can reject requests that don't come from Telegram.
TELEGRAM_WEBHOOK_SECRET=""

# --- Slack (optional — work messages / "waiting on someone") ---
# api.slack.com/apps -> Create New App -> OAuth & Permissions
# -> Redirect URL: {NEXTAUTH_URL}/api/integrations/slack/callback
SLACK_CLIENT_ID=""
SLACK_CLIENT_SECRET=""

# --- Notion (optional — save documents/invoices) ---
# notion.so/my-integrations -> New integration -> "Public" -> OAuth Domain & URIs
# -> Redirect URI: {NEXTAUTH_URL}/api/integrations/notion/callback
NOTION_CLIENT_ID=""
NOTION_CLIENT_SECRET=""

# --- AI extraction ---
# console.anthropic.com -> API keys. Haiku is cheap and plenty for this classification task.
ANTHROPIC_API_KEY=""
AIME_HEREDOC_EOF_9f2c

cat > ".gitignore" << 'AIME_HEREDOC_EOF_9f2c'
node_modules
.next
.env
.env.local
*.log
AIME_HEREDOC_EOF_9f2c

cat > "README.md" << 'AIME_HEREDOC_EOF_9f2c'
# AiMe

A personal action-layer assistant for a small household — you, and whoever you invite.
Email/password login, per-person connected accounts, encrypted tokens, and a scheduled
sync that turns Gmail into tasks.

## What's real here vs. what's a next step

**Fully wired, end to end:**
- Email/password auth (bcrypt-hashed, JWT sessions)
- Household model: one household, multiple members, each with their own login
- Google OAuth (Gmail read, Calendar read + explicit-click write, Drive read), tokens
  encrypted with AES-256-GCM before they touch the database
- Telegram, as the working substitute for WhatsApp (see below) — deep-link connect,
  webhook ingestion, tasks created from messages
- A cron job (`/api/cron/sync`) that polls connected Gmail accounts every 15 minutes,
  runs each candidate message through Claude for extraction, and creates tasks
- Onboarding that chains all of the above into one flow

**Connected, but ingestion logic is a stub:**
- Slack and Notion OAuth both work end to end and store an encrypted token — but nothing
  reads Slack messages or writes to Notion yet. That's the next piece of `lib/`, following
  the same pattern as `lib/gmail.ts`.

**Deliberately not built:**
- **WhatsApp.** There is no API for reading a personal WhatsApp account — Meta only
  exposes the WhatsApp Business API, which requires a registered business phone number
  and app review. Telegram's Bot API is open and free and does the same job for a small
  group of people who are willing to message a bot instead.
- **Banking/Plaid.** Real bank-read access is a much bigger compliance and liability step
  than a personal project needs. The onboarding shows why this is out of scope rather
  than pretending otherwise.

The rich Today/Tasks/Inbox/Calendar interface from the earlier prototype isn't ported
into this codebase yet — the dashboard here is intentionally plain, reading real data
from the real database. Porting that UI in as React components is the natural next step
once the backend feels solid.

## Setup

### 1. Database
Any Postgres works — [Neon](https://neon.tech) or Vercel Postgres both have a free tier
that's plenty for a household. Set `DATABASE_URL`, then:

```
npm install
npx prisma migrate dev --name init
```

### 2. Secrets
Copy `.env.example` to `.env` and fill in:
```
openssl rand -base64 32   # → NEXTAUTH_SECRET
openssl rand -base64 32   # → ENCRYPTION_KEY
openssl rand -base64 32   # → CRON_SECRET
```

### 3. Google (Gmail, Calendar, Drive)
1. [console.cloud.google.com](https://console.cloud.google.com) → new project.
2. APIs & Services → OAuth consent screen → leave it in **Testing** mode.
   In Testing mode Google never reviews your app, and only the specific Google accounts
   you add as **test users** (up to 100) can ever sign in — this is what makes a
   household-scale app safe to run without Google's verification process.
3. Add your and your family's Gmail addresses as test users.
4. Credentials → Create credentials → OAuth client ID → Web application.
   Authorized redirect URI: `{NEXTAUTH_URL}/api/integrations/google/callback`
5. Enable the Gmail API, Calendar API, and Drive API for the project.
6. Put the client ID/secret in `.env`.

### 4. Telegram
1. Message [@BotFather](https://t.me/BotFather) → `/newbot` → follow the prompts.
2. Put the token and the bot's `@username` in `.env`.
3. After deploying, register the webhook once (replace the placeholders):
   ```
   curl "https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://your-app.vercel.app/api/integrations/telegram/webhook&secret_token=<TELEGRAM_WEBHOOK_SECRET>"
   ```

### 5. Slack (optional)
[api.slack.com/apps](https://api.slack.com/apps) → Create New App → OAuth & Permissions
→ set the redirect URL to `{NEXTAUTH_URL}/api/integrations/slack/callback`.

### 6. Notion (optional)
[notion.so/my-integrations](https://notion.so/my-integrations) → New integration →
make it "Public" → set the redirect URI to `{NEXTAUTH_URL}/api/integrations/notion/callback`.

### 7. Anthropic
Get a key at [console.anthropic.com](https://console.anthropic.com). The extraction
step uses Haiku by default (`src/lib/extract.ts`) since it runs once per candidate
message — cheap and fast is the right trade-off there.

### 8. Deploy
Push to a GitHub repo, import it in Vercel, paste in the same env vars (with
`NEXTAUTH_URL` set to your real Vercel URL), and deploy. `vercel.json` registers the
15-minute sync cron automatically.

## Security notes
- No OAuth token is ever stored in plaintext — everything in `Integration.accessTokenEnc`
  / `refreshTokenEnc` is AES-256-GCM ciphertext, decrypted only in memory, only when a
  request needs it.
- Payments, sends, and calendar writes are never automatic — every route that would take
  an action requires the click that triggers it.
- Google scopes are read-only except calendar writes, which only happen from the explicit
  "Add to calendar" click (`api/calendar/add`).
- The Telegram webhook checks a shared secret header so only Telegram's servers can
  reach it.
- Deleting a household member's account (not yet built) should cascade-delete their
  Integration rows — token revocation with the provider itself is a good follow-up.
AIME_HEREDOC_EOF_9f2c

cat > "next.config.mjs" << 'AIME_HEREDOC_EOF_9f2c'
/** @type {import('next').NextConfig} */
const nextConfig = {};
export default nextConfig;
AIME_HEREDOC_EOF_9f2c

cat > "package.json" << 'AIME_HEREDOC_EOF_9f2c'
{
  "name": "aime",
  "private": true,
  "version": "0.1.0",
  "scripts": {
    "dev": "next dev",
    "build": "prisma generate && next build",
    "start": "next start",
    "prisma:migrate": "prisma migrate dev",
    "prisma:studio": "prisma studio"
  },
  "dependencies": {
    "next": "14.2.5",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "next-auth": "^4.24.7",
    "@prisma/client": "^5.18.0",
    "bcryptjs": "^2.4.3",
    "googleapis": "^140.0.1"
  },
  "devDependencies": {
    "prisma": "^5.18.0",
    "typescript": "^5.5.4",
    "@types/node": "^20.14.15",
    "@types/react": "^18.3.3",
    "@types/bcryptjs": "^2.4.6"
  }
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "prisma"
cat > "prisma/schema.prisma" << 'AIME_HEREDOC_EOF_9f2c'
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

generator client {
  provider = "prisma-client-js"
}

// A household is the "couple's account" — a small group who share visibility
// into shared tasks. Each member still has their own login and their own
// connected accounts; nothing about one person's Gmail is visible to another
// unless a task is explicitly marked shared.
model Household {
  id         String   @id @default(cuid())
  name       String
  inviteCode String   @unique
  createdAt  DateTime @default(now())

  members User[]
  tasks   Task[]
}

model User {
  id           String   @id @default(cuid())
  household    Household @relation(fields: [householdId], references: [id])
  householdId  String
  name         String
  email        String   @unique
  passwordHash String
  role         String   @default("member") // "owner" | "member"
  proactivity  String   @default("balanced") // "gentle" | "balanced" | "proactive"
  createdAt    DateTime @default(now())

  integrations   Integration[]
  tasks          Task[]
  activity       ActivityEvent[]
  pendingLinks   PendingLink[]
}

// One row per connected service per person. Tokens are encrypted (see lib/crypto.ts)
// before they're ever written here — the database holds ciphertext, never a raw token.
model Integration {
  id              String    @id @default(cuid())
  user            User      @relation(fields: [userId], references: [id])
  userId          String
  provider        String    // "google" | "telegram" | "slack" | "notion"
  status          String    @default("connected") // "connected" | "error" | "disconnected"
  accountLabel    String?
  externalId      String?   // e.g. Telegram chat id, Slack team id, Notion workspace id
  accessTokenEnc  String?
  refreshTokenEnc String?
  scope           String?
  expiresAt       DateTime?
  lastSyncAt      DateTime?
  createdAt       DateTime  @default(now())

  @@unique([userId, provider])
}

model Task {
  id          String    @id @default(cuid())
  household   Household @relation(fields: [householdId], references: [id])
  householdId String
  user        User      @relation(fields: [userId], references: [id])
  userId      String

  title      String
  type       String   @default("task") // bill | message | document | appointment | task
  source     String   // gmail | telegram | slack | notion | manual
  category   String   @default("personal")
  priority   String   @default("normal") // urgent | high | normal | low
  status     String   @default("open")   // open | waiting | completed | dismissed
  visibility String   @default("private") // private | household

  due       DateTime?
  amount    Float?
  currency  String?
  aiSummary String?
  why       String?

  // De-dupe key: e.g. a Gmail message id or "telegram:<chatId>:<messageId>".
  // Prevents the same email being turned into two tasks on the next sync.
  sourceRef String?

  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  @@unique([userId, sourceRef])
}

model ActivityEvent {
  id        String   @id @default(cuid())
  user      User     @relation(fields: [userId], references: [id])
  userId    String
  text      String
  kind      String   @default("tasks") // tasks | messages | documents | calendar | automations
  createdAt DateTime @default(now())
}

// Short-lived codes used to link a Telegram chat (or similar) back to a signed-in user
// during onboarding, without ever asking Telegram for a phone number or contact list.
model PendingLink {
  id        String   @id @default(cuid())
  code      String   @unique
  user      User     @relation(fields: [userId], references: [id])
  userId    String
  provider  String
  createdAt DateTime @default(now())
  expiresAt DateTime
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/auth/[...nextauth]"
cat > "src/app/api/auth/[...nextauth]/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import NextAuth from "next-auth";
import { authOptions } from "@/lib/auth";

const handler = NextAuth(authOptions);
export { handler as GET, handler as POST };
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/calendar/add"
cat > "src/app/api/calendar/add/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { getCalendarClient } from "@/lib/gmail";

// This route only ever runs when a person clicks "Add to calendar" in the UI —
// there is no code path anywhere that calls it without that click.
export async function POST(req: Request) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const userId = (session.user as any).id;

  const { title, start, end } = await req.json().catch(() => ({}));
  if (!title || !start || !end) {
    return NextResponse.json({ error: "title, start, and end are required" }, { status: 400 });
  }

  const integration = await prisma.integration.findUnique({
    where: { userId_provider: { userId, provider: "google" } },
  });
  if (!integration) return NextResponse.json({ error: "Google isn't connected" }, { status: 400 });

  const calendar = await getCalendarClient(integration);
  const event = await calendar.events.insert({
    calendarId: "primary",
    requestBody: { summary: title, start: { dateTime: start }, end: { dateTime: end } },
  });

  await prisma.activityEvent.create({
    data: { userId, text: `Added "${title}" to your calendar.`, kind: "calendar" },
  });

  return NextResponse.json({ ok: true, eventId: event.data.id });
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/cron/sync"
cat > "src/app/api/cron/sync/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { getGmailClient, listCandidateMessages } from "@/lib/gmail";
import { extractTask } from "@/lib/extract";

// Registered in vercel.json to run on a schedule. Vercel signs cron requests with
// an Authorization header matching CRON_SECRET — anyone else calling this gets 401.
export async function GET(req: Request) {
  const auth = req.headers.get("authorization");
  if (auth !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const integrations = await prisma.integration.findMany({
    where: { provider: "google", status: "connected" },
  });

  let created = 0;
  for (const integration of integrations) {
    try {
      const gmail = await getGmailClient(integration);
      const messages = await listCandidateMessages(gmail);

      for (const msg of messages) {
        // Already turned into a task on a previous run — skip without spending an AI call.
        const existing = await prisma.task.findUnique({
          where: { userId_sourceRef: { userId: integration.userId, sourceRef: msg.id } },
        });
        if (existing) continue;

        const text = `From: ${msg.from}\nSubject: ${msg.subject}\n\n${msg.snippet}`;
        const extracted = await extractTask("Gmail", text);
        if (!extracted?.isActionable) continue;

        const user = await prisma.user.findUnique({ where: { id: integration.userId } });
        if (!user) continue;

        await prisma.task.create({
          data: {
            userId: user.id,
            householdId: user.householdId,
            sourceRef: msg.id,
            source: "gmail",
            title: extracted.title || msg.subject,
            type: extracted.type || "task",
            category: extracted.category || "personal",
            priority: extracted.priority || "normal",
            amount: extracted.amount ?? null,
            currency: extracted.currency ?? null,
            due: extracted.dueDate ? new Date(extracted.dueDate) : null,
            aiSummary: extracted.whySummary || null,
            why: `Found in an email from ${msg.from}, subject "${msg.subject}".`,
          },
        });
        await prisma.activityEvent.create({
          data: { userId: user.id, text: `Found "${extracted.title || msg.subject}" in Gmail.`, kind: "tasks" },
        });
        created++;
      }

      await prisma.integration.update({ where: { id: integration.id }, data: { lastSyncAt: new Date() } });
    } catch (err) {
      console.error(`Sync failed for integration ${integration.id}`, err);
      await prisma.integration.update({ where: { id: integration.id }, data: { status: "error" } }).catch(() => {});
    }
  }

  return NextResponse.json({ ok: true, checked: integrations.length, tasksCreated: created });
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/household"
cat > "src/app/api/household/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });

  const household = await prisma.household.findUnique({
    where: { id: (session.user as any).householdId },
    include: { members: { select: { id: true, name: true, email: true, role: true } } },
  });
  return NextResponse.json({ household });
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/integrations/google/callback"
cat > "src/app/api/integrations/google/callback/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
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

  const oauth2Client = createGoogleOAuthClient();
  const { tokens } = await oauth2Client.getToken(code);

  oauth2Client.setCredentials(tokens);
  const oauth2 = require("googleapis").google.oauth2({ version: "v2", auth: oauth2Client });
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
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/integrations/google/connect"
cat > "src/app/api/integrations/google/connect/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
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
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/integrations/notion/callback"
cat > "src/app/api/integrations/notion/callback/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
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
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/integrations/notion/connect"
cat > "src/app/api/integrations/notion/connect/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.redirect(new URL("/login", process.env.NEXTAUTH_URL));

  const redirectUri = `${process.env.NEXTAUTH_URL}/api/integrations/notion/callback`;
  const params = new URLSearchParams({
    client_id: process.env.NOTION_CLIENT_ID || "",
    response_type: "code",
    owner: "user",
    redirect_uri: redirectUri,
    state: (session.user as any).id,
  });

  return NextResponse.redirect(`https://api.notion.com/v1/oauth/authorize?${params.toString()}`);
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/integrations/slack/callback"
cat > "src/app/api/integrations/slack/callback/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
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
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/integrations/slack/connect"
cat > "src/app/api/integrations/slack/connect/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
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
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/integrations/status"
cat > "src/app/api/integrations/status/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });

  const integrations = await prisma.integration.findMany({
    where: { userId: (session.user as any).id },
    select: { provider: true, status: true, accountLabel: true, lastSyncAt: true },
  });

  return NextResponse.json({ integrations });
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/integrations/telegram/connect"
cat > "src/app/api/integrations/telegram/connect/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { randomCode } from "@/lib/crypto";

// Telegram has no concept of OAuth for this: instead, we hand the browser a short
// code and a deep link. The person taps it, Telegram opens a chat with the bot and
// sends "/start <code>" automatically, and the webhook (see ../webhook) matches
// that code back to this signed-in user. No phone number or contact list is ever read.
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const userId = (session.user as any).id;

  const code = randomCode(6);
  await prisma.pendingLink.create({
    data: { code, userId, provider: "telegram", expiresAt: new Date(Date.now() + 15 * 60 * 1000) },
  });

  const username = process.env.TELEGRAM_BOT_USERNAME;
  return NextResponse.json({
    code,
    deepLink: username ? `https://t.me/${username}?start=${code}` : null,
  });
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/integrations/telegram/status"
cat > "src/app/api/integrations/telegram/status/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });

  const integration = await prisma.integration.findUnique({
    where: { userId_provider: { userId: (session.user as any).id, provider: "telegram" } },
  });

  return NextResponse.json({ connected: integration?.status === "connected" });
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/integrations/telegram/webhook"
cat > "src/app/api/integrations/telegram/webhook/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { extractTask } from "@/lib/extract";

async function reply(chatId: number | string, text: string) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) return;
  await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, text }),
  }).catch(() => {});
}

export async function POST(req: Request) {
  // Telegram sends this header when a secret_token was set on setWebhook (see README).
  // Anyone else hitting this URL is rejected before we read the body.
  const secret = req.headers.get("x-telegram-bot-api-secret-token");
  if (process.env.TELEGRAM_WEBHOOK_SECRET && secret !== process.env.TELEGRAM_WEBHOOK_SECRET) {
    return NextResponse.json({ ok: false }, { status: 401 });
  }

  const update = await req.json().catch(() => null);
  const message = update?.message;
  if (!message?.chat?.id || typeof message.text !== "string") {
    return NextResponse.json({ ok: true }); // ignore non-text updates (stickers, edits, etc.)
  }

  const chatId: number = message.chat.id;
  const text: string = message.text.trim();

  // Step 1: linking. "/start <code>" arrives the moment someone taps the deep link.
  if (text.startsWith("/start")) {
    const code = text.split(" ")[1];
    const pending = code
      ? await prisma.pendingLink.findUnique({ where: { code } })
      : null;

    if (!pending || pending.provider !== "telegram" || pending.expiresAt < new Date()) {
      await reply(chatId, "That link has expired. Go back to AiMe and tap Connect Telegram again.");
      return NextResponse.json({ ok: true });
    }

    await prisma.integration.upsert({
      where: { userId_provider: { userId: pending.userId, provider: "telegram" } },
      create: { userId: pending.userId, provider: "telegram", status: "connected", externalId: String(chatId) },
      update: { status: "connected", externalId: String(chatId) },
    });
    await prisma.pendingLink.delete({ where: { id: pending.id } });
    await prisma.activityEvent.create({
      data: { userId: pending.userId, text: "Connected Telegram.", kind: "automations" },
    });
    await reply(chatId, "Connected! Message me things like \u201cremind me to call David tomorrow\u201d and I'll turn them into tasks.");
    return NextResponse.json({ ok: true });
  }

  // Step 2: ordinary message from an already-linked chat — try to extract a task.
  const integration = await prisma.integration.findFirst({
    where: { provider: "telegram", externalId: String(chatId), status: "connected" },
  });
  if (!integration) {
    await reply(chatId, "I don't recognize this chat yet. Connect Telegram from AiMe first.");
    return NextResponse.json({ ok: true });
  }

  const sourceRef = `telegram:${chatId}:${message.message_id}`;
  const extracted = await extractTask("Telegram message", text).catch(() => null);

  if (!extracted?.isActionable) {
    await reply(chatId, "Noted — nothing for me to track there.");
    return NextResponse.json({ ok: true });
  }

  const user = await prisma.user.findUnique({ where: { id: integration.userId } });
  if (!user) return NextResponse.json({ ok: true });

  await prisma.task.upsert({
    where: { userId_sourceRef: { userId: user.id, sourceRef } },
    create: {
      userId: user.id,
      householdId: user.householdId,
      sourceRef,
      source: "telegram",
      title: extracted.title || text.slice(0, 60),
      type: extracted.type || "task",
      category: extracted.category || "personal",
      priority: extracted.priority || "normal",
      due: extracted.dueDate ? new Date(extracted.dueDate) : null,
      aiSummary: extracted.whySummary || null,
      why: `Detected in a Telegram message: \u201c${text.slice(0, 140)}\u201d`,
    },
    update: {},
  });

  await prisma.activityEvent.create({
    data: { userId: user.id, text: `Detected a reminder in Telegram.`, kind: "messages" },
  });

  await reply(chatId, `Got it — added \u201c${extracted.title || text.slice(0, 60)}\u201d to your tasks.`);
  return NextResponse.json({ ok: true });
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/signup"
cat > "src/app/api/signup/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
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
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/tasks"
cat > "src/app/api/tasks/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
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
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/user/proactivity"
cat > "src/app/api/user/proactivity/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";

export async function POST(req: Request) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });

  const { level } = await req.json().catch(() => ({}));
  if (!["gentle", "balanced", "proactive"].includes(level)) {
    return NextResponse.json({ error: "Invalid level" }, { status: 400 });
  }

  await prisma.user.update({ where: { id: (session.user as any).id }, data: { proactivity: level } });
  return NextResponse.json({ ok: true });
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/dashboard"
cat > "src/app/dashboard/page.tsx" << 'AIME_HEREDOC_EOF_9f2c'
"use client";
import { useEffect, useState } from "react";
import { useSession, signOut } from "next-auth/react";
import Link from "next/link";

type Task = {
  id: string; title: string; type: string; source: string; priority: string; status: string;
  due: string | null; amount: number | null; currency: string | null; aiSummary: string | null;
  user: { name: string };
};

export default function Dashboard() {
  const { data: session } = useSession();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);

  async function load() {
    setLoading(true);
    const res = await fetch("/api/tasks");
    const data = await res.json();
    setTasks(data.tasks ?? []);
    setLoading(false);
  }

  useEffect(() => { load(); }, []);

  async function complete(id: string) {
    await fetch("/api/tasks", {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id, status: "completed" }),
    });
    load();
  }

  const open = tasks.filter((t) => t.status !== "completed");
  const done = tasks.filter((t) => t.status === "completed");

  return (
    <div>
      <div className="topbar">
        <b>AiMe</b>
        <span style={{ color: "var(--text-2)", fontSize: 13 }}>{session?.user?.name}</span>
        <div style={{ flex: 1 }} />
        <Link className="btn" style={{ width: "auto" }} href="/household">Household</Link>
        <button className="btn" style={{ width: "auto" }} onClick={() => signOut({ callbackUrl: "/login" })}>Sign out</button>
      </div>
      <div className="content">
        <h1 style={{ fontSize: 26, letterSpacing: "-.02em" }}>Today</h1>
        {loading ? (
          <p style={{ color: "var(--text-2)" }}>Loading…</p>
        ) : open.length === 0 ? (
          <p style={{ color: "var(--text-2)" }}>
            Nothing here yet. Connected accounts sync automatically every 15 minutes — or trigger the cron
            endpoint manually while testing.
          </p>
        ) : (
          open.map((t) => (
            <div className="row" key={t.id}>
              <div className="t">
                <b>{t.title}{t.amount ? ` · ${t.currency ?? ""}${t.amount}` : ""}</b>
                <small>{t.aiSummary ?? `${t.source} · ${t.priority}`}{t.due ? ` · Due ${new Date(t.due).toLocaleDateString()}` : ""}</small>
              </div>
              <button className="btn" style={{ width: "auto" }} onClick={() => complete(t.id)}>Complete</button>
            </div>
          ))
        )}

        {done.length > 0 && (
          <>
            <h2 style={{ fontSize: 15, marginTop: 28, color: "var(--text-2)" }}>Completed</h2>
            {done.map((t) => (
              <div className="row" key={t.id} style={{ opacity: 0.6 }}>
                <div className="t"><b style={{ textDecoration: "line-through" }}>{t.title}</b></div>
              </div>
            ))}
          </>
        )}
      </div>
    </div>
  );
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app"
cat > "src/app/globals.css" << 'AIME_HEREDOC_EOF_9f2c'
:root{
  --bg:#F6F5F3; --surface:#FFFFFF; --surface-2:#FAF9F7; --border:#E6E2DD; --border-2:#D6D1C9;
  --text:#23211F; --text-2:#6B6660; --text-3:#9A958E;
  --accent:#0E7C86; --accent-2:#0A616A; --accent-weak:#E2F0F1; --accent-line:#BEDFE1;
  --red:#B03A2C; --red-weak:#FBEAE6; --green:#2C7357; --green-weak:#E3F0E9;
  --sans:ui-sans-serif,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font-family:var(--sans);font-size:14px;line-height:1.5}
a{color:var(--accent)}
button,input{font:inherit}
.shell{min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px}
.panel{width:100%;max-width:420px;background:var(--surface);border:1px solid var(--border);border-radius:14px;padding:28px}
.panel h1{font-size:22px;font-weight:600;letter-spacing:-.02em;margin:0 0 6px}
.panel p.lead{color:var(--text-2);font-size:13.5px;margin:0 0 20px}
.field{margin-bottom:14px;display:flex;flex-direction:column;gap:5px}
.field label{font-size:12.5px;color:var(--text-2)}
.input{height:38px;border:1px solid var(--border);border-radius:8px;padding:0 11px;font-size:14px;background:var(--surface)}
.input:focus{outline:2px solid var(--accent);outline-offset:-1px;border-color:transparent}
.btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;height:38px;padding:0 14px;
  border-radius:8px;border:1px solid var(--border-2);background:var(--surface);font-size:14px;font-weight:500;
  color:var(--text);cursor:pointer;width:100%}
.btn.primary{background:var(--accent);border-color:var(--accent);color:#fff}
.btn.primary:hover{background:var(--accent-2)}
.btn:disabled{opacity:.55;cursor:default}
.seg{display:flex;border:1px solid var(--border);border-radius:8px;overflow:hidden;margin-bottom:16px}
.seg button{flex:1;padding:8px;font-size:13px;color:var(--text-2);background:none;border:none;cursor:pointer}
.seg button.on{background:var(--accent);color:#fff}
.error{background:var(--red-weak);color:var(--red);border-radius:8px;padding:9px 11px;font-size:13px;margin-bottom:14px}
.foot{margin-top:16px;text-align:center;font-size:13px;color:var(--text-2)}

.ob-card{width:100%;max-width:560px;background:var(--surface);border:1px solid var(--border);border-radius:14px;padding:30px}
.ob-card h1{font-size:26px;font-weight:600;letter-spacing:-.02em;margin:0 0 8px}
.ob-card p.lead{color:var(--text-2);font-size:14.5px;margin:0 0 22px;max-width:46ch}
.conn-row{display:flex;gap:12px;align-items:center;border:1px solid var(--border);border-radius:11px;padding:14px;margin-bottom:10px}
.conn-row .logo{width:34px;height:34px;border-radius:9px;background:var(--surface-2);display:grid;place-items:center;flex:none}
.conn-row .grow{flex:1;min-width:0}
.conn-row b{display:block;font-size:14.5px}
.conn-row small{color:var(--text-2);font-size:12.5px}
.pill{display:inline-flex;align-items:center;gap:5px;height:22px;padding:0 9px;border-radius:999px;font-size:12px;font-weight:500;background:var(--surface-2);color:var(--text-2)}
.pill.green{background:var(--green-weak);color:var(--green)}
.steps{display:flex;gap:5px;margin-top:22px}
.steps i{flex:1;height:3px;border-radius:2px;background:var(--border-2)}
.steps i.on{background:var(--accent)}
.code-box{display:flex;align-items:center;gap:10px;background:var(--surface-2);border:1px dashed var(--border-2);
  border-radius:9px;padding:12px 14px;font-family:ui-monospace,monospace;font-size:14px}

.topbar{display:flex;align-items:center;gap:14px;padding:14px 22px;border-bottom:1px solid var(--border);background:var(--surface)}
.topbar b{font-size:15px}
.content{max-width:860px;margin:0 auto;padding:28px 20px 60px}
.row{display:flex;gap:12px;align-items:center;padding:12px 14px;border:1px solid var(--border);border-radius:10px;background:var(--surface);margin-bottom:8px}
.row .t{flex:1;min-width:0}
.row .t b{display:block;font-size:14px}
.row .t small{color:var(--text-2);font-size:12.5px}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/household"
cat > "src/app/household/page.tsx" << 'AIME_HEREDOC_EOF_9f2c'
"use client";
import { useEffect, useState } from "react";
import Link from "next/link";

type Household = { name: string; inviteCode: string; members: { id: string; name: string; email: string; role: string }[] };

export default function HouseholdPage() {
  const [household, setHousehold] = useState<Household | null>(null);

  useEffect(() => {
    fetch("/api/household").then((r) => r.json()).then((d) => setHousehold(d.household));
  }, []);

  return (
    <div>
      <div className="topbar">
        <b>AiMe</b>
        <div style={{ flex: 1 }} />
        <Link className="btn" style={{ width: "auto" }} href="/dashboard">Back to Today</Link>
      </div>
      <div className="content">
        <h1 style={{ fontSize: 26, letterSpacing: "-.02em" }}>Household</h1>
        {household && (
          <>
            <p style={{ color: "var(--text-2)" }}>
              Share this code with a partner or family member. When they sign up and choose
              "Join with a code," they'll land in the same household with their own login and
              their own connected accounts.
            </p>
            <div className="code-box" style={{ marginBottom: 20 }}>{household.inviteCode}</div>
            {household.members.map((m) => (
              <div className="row" key={m.id}>
                <div className="t"><b>{m.name}</b><small>{m.email} · {m.role}</small></div>
              </div>
            ))}
          </>
        )}
      </div>
    </div>
  );
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app"
cat > "src/app/layout.tsx" << 'AIME_HEREDOC_EOF_9f2c'
import "./globals.css";
import { Providers } from "./providers";

export const metadata = { title: "AiMe" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/login"
cat > "src/app/login/page.tsx" << 'AIME_HEREDOC_EOF_9f2c'
"use client";
import { useState } from "react";
import { signIn } from "next-auth/react";
import { useRouter } from "next/navigation";
import Link from "next/link";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    const res = await signIn("credentials", { email, password, redirect: false });
    setLoading(false);
    if (res?.error) setError("That email and password don't match.");
    else router.push("/dashboard");
  }

  return (
    <div className="shell">
      <form className="panel" onSubmit={submit}>
        <h1>Welcome back</h1>
        <p className="lead">Sign in to your AiMe account.</p>
        {error && <div className="error">{error}</div>}
        <div className="field">
          <label>Email</label>
          <input className="input" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        </div>
        <div className="field">
          <label>Password</label>
          <input className="input" type="password" required value={password} onChange={(e) => setPassword(e.target.value)} />
        </div>
        <button className="btn primary" disabled={loading}>{loading ? "Signing in…" : "Sign in"}</button>
        <p className="foot">No account yet? <Link href="/signup">Create one</Link></p>
      </form>
    </div>
  );
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/onboarding"
cat > "src/app/onboarding/onboarding-client.tsx" << 'AIME_HEREDOC_EOF_9f2c'
"use client";
import { useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";

type Status = { integrations: { provider: string; status: string; accountLabel?: string }[] };

export default function OnboardingClient() {
  const router = useRouter();
  const params = useSearchParams();
  const [step, setStep] = useState(0);
  const [status, setStatus] = useState<Status>({ integrations: [] });
  const [telegram, setTelegram] = useState<{ code: string; deepLink: string | null } | null>(null);
  const [household, setHousehold] = useState<{ name: string; inviteCode: string } | null>(null);
  const [level, setLevel] = useState<"gentle" | "balanced" | "proactive">("balanced");

  async function refreshStatus() {
    const res = await fetch("/api/integrations/status");
    if (res.ok) setStatus(await res.json());
  }

  useEffect(() => {
    refreshStatus();
    fetch("/api/household").then((r) => r.json()).then((d) => setHousehold(d.household));
    // Google/Slack/Notion land back here via a redirect with ?connected=<provider>.
    if (params.get("connected")) {
      refreshStatus();
      setStep((s) => Math.max(s, 1));
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const isConnected = (provider: string) =>
    status.integrations.some((i) => i.provider === provider && i.status === "connected");

  async function startTelegram() {
    const res = await fetch("/api/integrations/telegram/connect");
    const data = await res.json();
    setTelegram(data);
    // Poll every 2s for up to a couple minutes until the webhook links the chat.
    const interval = setInterval(async () => {
      const r = await fetch("/api/integrations/telegram/status");
      const d = await r.json();
      if (d.connected) {
        clearInterval(interval);
        refreshStatus();
      }
    }, 2000);
    setTimeout(() => clearInterval(interval), 180000);
  }

  async function finish() {
    await fetch("/api/user/proactivity", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ level }),
    });
    router.push("/dashboard");
  }

  const steps = [
    // Step 0 — welcome
    <div key="welcome">
      <h1>Meet AiMe</h1>
      <p className="lead">Your digital life is full of information. AiMe turns it into action — bills, replies, appointments, the small things that fall through the cracks.</p>
      {household && (
        <div className="conn-row">
          <span className="logo">🏠</span>
          <div className="grow">
            <b>{household.name}</b>
            <small>Invite code for a partner or family member: <code>{household.inviteCode}</code></small>
          </div>
        </div>
      )}
    </div>,

    // Step 1 — Google
    <div key="google">
      <h1>Connect Google</h1>
      <p className="lead">Gmail, Calendar and Drive are where most of what needs your attention shows up.</p>
      <div className="conn-row">
        <span className="logo">✉️</span>
        <div className="grow">
          <b>Gmail, Calendar &amp; Drive</b>
          <small>Read-only, except adding an event when you click "Add to calendar"</small>
        </div>
        {isConnected("google") ? (
          <span className="pill green">Connected</span>
        ) : (
          <a className="btn primary" style={{ width: "auto" }} href="/api/integrations/google/connect">Connect</a>
        )}
      </div>
    </div>,

    // Step 2 — Telegram (WhatsApp substitute)
    <div key="telegram">
      <h1>Connect Telegram</h1>
      <p className="lead">
        There's no way for any app to privately read your personal WhatsApp — Meta only allows that for
        business accounts. Telegram works the same way in practice: message the AiMe bot the way you'd
        message a friend, and it becomes a task.
      </p>
      <div className="conn-row">
        <span className="logo">💬</span>
        <div className="grow">
          <b>Telegram</b>
          <small>Only messages you send the bot directly — never your other chats</small>
        </div>
        {isConnected("telegram") ? (
          <span className="pill green">Connected</span>
        ) : (
          <button className="btn primary" style={{ width: "auto" }} onClick={startTelegram}>Connect</button>
        )}
      </div>
      {telegram && !isConnected("telegram") && (
        <div style={{ marginTop: 12 }}>
          {telegram.deepLink ? (
            <a className="btn" href={telegram.deepLink} target="_blank" rel="noreferrer">Open Telegram &amp; link automatically</a>
          ) : (
            <p className="lead" style={{ fontSize: 13 }}>
              Set TELEGRAM_BOT_USERNAME on the server, or message your bot manually with:
            </p>
          )}
          <div className="code-box" style={{ marginTop: 10 }}>/start {telegram.code}</div>
        </div>
      )}
    </div>,

    // Step 3 — optional extras
    <div key="extras">
      <h1>Anything else worth connecting?</h1>
      <p className="lead">Both are optional and can be added later from Settings.</p>
      <div className="conn-row">
        <span className="logo">💼</span>
        <div className="grow"><b>Slack</b><small>Surface work messages waiting on a reply</small></div>
        {isConnected("slack") ? <span className="pill green">Connected</span> :
          <a className="btn" style={{ width: "auto" }} href="/api/integrations/slack/connect">Connect</a>}
      </div>
      <div className="conn-row">
        <span className="logo">📄</span>
        <div className="grow"><b>Notion</b><small>File invoices and receipts automatically</small></div>
        {isConnected("notion") ? <span className="pill green">Connected</span> :
          <a className="btn" style={{ width: "auto" }} href="/api/integrations/notion/connect">Connect</a>}
      </div>
      <div className="conn-row" style={{ opacity: 0.6 }}>
        <span className="logo">📱</span>
        <div className="grow"><b>WhatsApp</b><small>Not available — no personal-account API exists yet</small></div>
        <span className="pill">Unavailable</span>
      </div>
    </div>,

    // Step 4 — proactivity
    <div key="level">
      <h1>How proactive should AiMe be?</h1>
      <p className="lead">You can change this later in Settings.</p>
      {([
        ["gentle", "Gentle", "Only notify me when something is important."],
        ["balanced", "Balanced", "Suggest actions and reminders."],
        ["proactive", "Proactive", "Take care of routine things automatically, within limits I set."],
      ] as const).map(([id, label, desc]) => (
        <div
          key={id}
          className="conn-row"
          style={{ cursor: "pointer", borderColor: level === id ? "var(--accent)" : undefined }}
          onClick={() => setLevel(id)}
        >
          <div className="grow"><b>{label}</b><small>{desc}</small></div>
          {level === id && <span className="pill green">Selected</span>}
        </div>
      ))}
    </div>,
  ];

  return (
    <div className="shell">
      <div className="ob-card">
        {steps[step]}
        <div style={{ display: "flex", gap: 10, marginTop: 22 }}>
          {step > 0 && <button className="btn" onClick={() => setStep(step - 1)}>Back</button>}
          {step < steps.length - 1 ? (
            <button className="btn primary" onClick={() => setStep(step + 1)}>Continue</button>
          ) : (
            <button className="btn primary" onClick={finish}>Go to Today</button>
          )}
        </div>
        <div className="steps">{steps.map((_, i) => <i key={i} className={i <= step ? "on" : ""} />)}</div>
      </div>
    </div>
  );
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/onboarding"
cat > "src/app/onboarding/page.tsx" << 'AIME_HEREDOC_EOF_9f2c'
import { Suspense } from "react";
import OnboardingClient from "./onboarding-client";

export default function OnboardingPage() {
  return (
    <Suspense fallback={null}>
      <OnboardingClient />
    </Suspense>
  );
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app"
cat > "src/app/page.tsx" << 'AIME_HEREDOC_EOF_9f2c'
import { redirect } from "next/navigation";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";

export default async function Home() {
  const session = await getServerSession(authOptions);
  redirect(session ? "/dashboard" : "/login");
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app"
cat > "src/app/providers.tsx" << 'AIME_HEREDOC_EOF_9f2c'
"use client";
import { SessionProvider } from "next-auth/react";

export function Providers({ children }: { children: React.ReactNode }) {
  return <SessionProvider>{children}</SessionProvider>;
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/signup"
cat > "src/app/signup/page.tsx" << 'AIME_HEREDOC_EOF_9f2c'
"use client";
import { useState } from "react";
import { signIn } from "next-auth/react";
import { useRouter } from "next/navigation";
import Link from "next/link";

export default function SignupPage() {
  const router = useRouter();
  const [mode, setMode] = useState<"create" | "join">("create");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [householdName, setHouseholdName] = useState("");
  const [inviteCode, setInviteCode] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    const res = await fetch("/api/signup", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ mode, name, email, password, householdName, inviteCode }),
    });
    const data = await res.json();
    if (!res.ok) {
      setLoading(false);
      setError(data.error || "Something went wrong.");
      return;
    }
    await signIn("credentials", { email, password, redirect: false });
    setLoading(false);
    router.push("/onboarding");
  }

  return (
    <div className="shell">
      <form className="panel" onSubmit={submit}>
        <h1>Create your account</h1>
        <p className="lead">One household can hold a couple of people, each with their own login.</p>
        {error && <div className="error">{error}</div>}
        <div className="seg">
          <button type="button" className={mode === "create" ? "on" : ""} onClick={() => setMode("create")}>Start a household</button>
          <button type="button" className={mode === "join" ? "on" : ""} onClick={() => setMode("join")}>Join with a code</button>
        </div>
        <div className="field">
          <label>Your name</label>
          <input className="input" required value={name} onChange={(e) => setName(e.target.value)} />
        </div>
        <div className="field">
          <label>Email</label>
          <input className="input" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        </div>
        <div className="field">
          <label>Password</label>
          <input className="input" type="password" required minLength={8} value={password} onChange={(e) => setPassword(e.target.value)} />
        </div>
        {mode === "create" ? (
          <div className="field">
            <label>Household name (e.g. "The Cohens")</label>
            <input className="input" value={householdName} onChange={(e) => setHouseholdName(e.target.value)} placeholder="Optional" />
          </div>
        ) : (
          <div className="field">
            <label>Invite code from whoever set up your household</label>
            <input className="input" required value={inviteCode} onChange={(e) => setInviteCode(e.target.value)} />
          </div>
        )}
        <button className="btn primary" disabled={loading}>{loading ? "Creating…" : "Continue"}</button>
        <p className="foot">Already have an account? <Link href="/login">Sign in</Link></p>
      </form>
    </div>
  );
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/lib"
cat > "src/lib/auth.ts" << 'AIME_HEREDOC_EOF_9f2c'
import type { NextAuthOptions } from "next-auth";
import CredentialsProvider from "next-auth/providers/credentials";
import { prisma } from "./db";
import { verifyPassword } from "./password";

// Note what this file is NOT: it is not where Gmail/Calendar/Slack/etc. connect.
// This is the one login that gets someone into their own AiMe account. Every
// other service is connected afterwards, per-person, under Settings, and its
// tokens live in the Integration table — never in a session or a cookie.
export const authOptions: NextAuthOptions = {
  session: { strategy: "jwt" },
  pages: { signIn: "/login" },
  providers: [
    CredentialsProvider({
      name: "Email and password",
      credentials: {
        email: { label: "Email", type: "email" },
        password: { label: "Password", type: "password" },
      },
      async authorize(credentials) {
        if (!credentials?.email || !credentials?.password) return null;
        const user = await prisma.user.findUnique({
          where: { email: credentials.email.toLowerCase().trim() },
        });
        if (!user) return null;
        const valid = await verifyPassword(credentials.password, user.passwordHash);
        if (!valid) return null;
        return {
          id: user.id,
          email: user.email,
          name: user.name,
          householdId: user.householdId,
        } as any;
      },
    }),
  ],
  callbacks: {
    async jwt({ token, user }) {
      if (user) {
        token.uid = (user as any).id;
        token.householdId = (user as any).householdId;
      }
      return token;
    },
    async session({ session, token }) {
      if (session.user) {
        (session.user as any).id = token.uid;
        (session.user as any).householdId = token.householdId;
      }
      return session;
    },
  },
};
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/lib"
cat > "src/lib/crypto.ts" << 'AIME_HEREDOC_EOF_9f2c'
import crypto from "crypto";

// Every OAuth access/refresh token is encrypted with this key before it is written
// to the database, and decrypted only in-memory, at the moment it's needed to call
// a provider's API. If the database ever leaked, the tokens inside it would not.
//
// ENCRYPTION_KEY must be a 32-byte key, base64-encoded (openssl rand -base64 32).
function getKey(): Buffer {
  const raw = process.env.ENCRYPTION_KEY;
  if (!raw) throw new Error("ENCRYPTION_KEY is not set");
  const key = Buffer.from(raw, "base64");
  if (key.length !== 32) {
    throw new Error("ENCRYPTION_KEY must decode to exactly 32 bytes");
  }
  return key;
}

// Output format: base64(iv) . base64(authTag) . base64(ciphertext)
export function encrypt(plaintext: string): string {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", getKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return [iv.toString("base64"), authTag.toString("base64"), ciphertext.toString("base64")].join(".");
}

export function decrypt(payload: string): string {
  const [ivB64, tagB64, dataB64] = payload.split(".");
  if (!ivB64 || !tagB64 || !dataB64) throw new Error("Malformed encrypted payload");
  const decipher = crypto.createDecipheriv("aes-256-gcm", getKey(), Buffer.from(ivB64, "base64"));
  decipher.setAuthTag(Buffer.from(tagB64, "base64"));
  const plaintext = Buffer.concat([decipher.update(Buffer.from(dataB64, "base64")), decipher.final()]);
  return plaintext.toString("utf8");
}

export function randomCode(bytes = 16): string {
  return crypto.randomBytes(bytes).toString("hex");
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/lib"
cat > "src/lib/db.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { PrismaClient } from "@prisma/client";

const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const prisma = globalForPrisma.prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== "production") globalForPrisma.prisma = prisma;
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/lib"
cat > "src/lib/extract.ts" << 'AIME_HEREDOC_EOF_9f2c'
import type { ExtractedTask } from "./types";

const SYSTEM_PROMPT = `You classify a single incoming message (an email or a chat message) for a personal
assistant app called AiMe. Decide whether it contains something the user needs to act on:
a bill, an appointment to confirm, a document to sign, a reminder request, or a direct
question waiting for a reply. Newsletters, marketing, and messages with no action are not actionable.

Respond with ONLY a JSON object, no prose, no markdown fences, matching exactly this shape:
{"isActionable": boolean, "title": string, "type": "bill"|"message"|"document"|"appointment"|"task",
 "category": "personal"|"work"|"finance"|"appointments"|"purchases",
 "priority": "urgent"|"high"|"normal"|"low", "amount": number|null, "currency": string|null,
 "dueDate": string|null, "whySummary": string}

"whySummary" is one short sentence explaining, in plain language, what in the message caused you to
create this task (e.g. "Contains an amount, a due date, and a payment link."). If isActionable is
false, still return valid JSON with isActionable:false and the other fields as null/empty.`;

// Haiku is intentionally used here: this call runs once per candidate message on every sync,
// so cost and latency matter far more than raw capability for a one-sentence classification task.
const MODEL = "claude-haiku-4-5-20251001";

export async function extractTask(sourceLabel: string, text: string): Promise<ExtractedTask | null> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY is not set");

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 300,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: `Source: ${sourceLabel}\n\nMessage:\n${text.slice(0, 4000)}` }],
    }),
  });

  if (!res.ok) {
    console.error("Anthropic extraction call failed", res.status, await res.text().catch(() => ""));
    return null;
  }

  const data = await res.json();
  const raw: string = data?.content?.find((b: any) => b.type === "text")?.text ?? "";
  const cleaned = raw.replace(/```json|```/g, "").trim();

  try {
    const parsed = JSON.parse(cleaned) as ExtractedTask;
    return parsed;
  } catch {
    console.error("Could not parse extraction response:", raw);
    return null;
  }
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/lib"
cat > "src/lib/gmail.ts" << 'AIME_HEREDOC_EOF_9f2c'
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
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/lib"
cat > "src/lib/google.ts" << 'AIME_HEREDOC_EOF_9f2c'
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
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/lib"
cat > "src/lib/password.ts" << 'AIME_HEREDOC_EOF_9f2c'
import bcrypt from "bcryptjs";

export function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, 12);
}

export function verifyPassword(plain: string, hash: string): Promise<boolean> {
  return bcrypt.compare(plain, hash);
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/lib"
cat > "src/lib/types.ts" << 'AIME_HEREDOC_EOF_9f2c'
export type ExtractedTask = {
  isActionable: boolean;
  title?: string;
  type?: "bill" | "message" | "document" | "appointment" | "task";
  category?: "personal" | "work" | "finance" | "appointments" | "purchases";
  priority?: "urgent" | "high" | "normal" | "low";
  amount?: number;
  currency?: string;
  dueDate?: string; // ISO date, if present
  whySummary?: string; // one sentence, shown to the user as "why AiMe created this"
};
AIME_HEREDOC_EOF_9f2c

cat > "tsconfig.json" << 'AIME_HEREDOC_EOF_9f2c'
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": false,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
AIME_HEREDOC_EOF_9f2c

cat > "vercel.json" << 'AIME_HEREDOC_EOF_9f2c'
{
  "crons": [
    { "path": "/api/cron/sync", "schedule": "0 6 * * *" }
  ]
}
AIME_HEREDOC_EOF_9f2c

echo "Done. Files created:"
find . -type f -not -path './.git/*' | sort
