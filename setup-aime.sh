setup-aime.sh#!/usr/bin/env bash
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

# --- Chat assistant ---
# aistudio.google.com/apikey -> Create API key. Free tier is generous for personal use.
# This powers the /chat page, separate from the Anthropic key above which only does the
# quiet background bill/appointment extraction.
GEMINI_API_KEY=""
GEMINI_MODEL="gemini-3.6-flash"
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
- A `/chat` page backed by Gemini, with read-only tools to search your tasks, Gmail,
  and Calendar, and to see recent activity — it looks things up for real, but never
  sends, pays, or changes anything (see `lib/assistant-tools.ts`)
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

### 8. Gemini (for the /chat page)
Get a key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey) — no
Google Cloud project or OAuth consent screen needed, just an API key. Put it in
`GEMINI_API_KEY`. This is separate from the Google OAuth client in step 3: that one
lets AiMe *read* Gmail/Calendar on your behalf; this key is what lets the chat
assistant *reason* over what it finds there.

Since this feature adds a new database table, run one more migration after pulling
in this change:
```
npx prisma migrate dev --name add_chat
```

### 9. Deploy
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
    "next": "14.2.35",
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
  chatMessages   ChatMessage[]
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
  // A real link pulled from the source email's body (e.g. a payment page) — never
  // invented by the AI, only ever a URL that actually appeared in the message.
  actionUrl String?

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

// One row per message in the "chat with your assistant" feature. The assistant
// (Gemini) only ever reads through tool calls defined in lib/assistant-tools.ts —
// it never writes, sends, or pays anything from a chat turn.
model ChatMessage {
  id        String   @id @default(cuid())
  user      User     @relation(fields: [userId], references: [id])
  userId    String
  role      String   // "user" | "model"
  content   String
  createdAt DateTime @default(now())
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "public"
base64 -d > "public/logo-full.png" << 'AIME_HEREDOC_EOF_9f2c'
iVBORw0KGgoAAAANSUhEUgAAA+sAAAFUCAYAAABcA63AAAEAAElEQVR4nOy9d4BlR3Um/p26977XaXJWAEWEW0Q3YIKgJUAwgIh2
SyIYYcAjDEhagg3G9rZ6vQ67jpi1/WPWu9heR/V6bWzAcgLaBpugARPUKDGa0eTOufu9d2+d3x+3wqn73gzBI2lmVJ/U8967t25V
3VR1vpMKiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI
iIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI
iIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI
iIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI
iIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIg4C0CPdgciIh558H/guSc+ff2IiIiIiIiIiIiIiIjojEjWI85tMBNuBw0C
6uqrgfFJKLvrbvFvO64EAHRfAh7YB8xuAu3/x32MAaDvCQO8/XfAo6NgQ94jgY+IiIiIiIiIiDhbQIjy61mBSNYjzn6wsZQbUr50
Hmjb2v3q8ssvx/33A6tPQTF2DeWnu9mhOzjp31a+Q8fu20f3Hh3gMUBjxA5+0QofEREREREREREREfH9IZL1iLMTzIRRqCHcnfQs
96r6ky8qdi2CRzqQ8m3v/GbfS39w+85G0eiuU/oD2zb3PmF5tahNLurenGuUA4lmZKx1QgkTKGFmcKKUJp0XW3pQ7NyU8PJq8eCh
A6vf7N6QreS1xrH/98ujx/HAbQ3Z1tAdnOBuJMYwX4xeD13uicQ9IiIiIiIiIiIiIuK7RyTrEWcRmAaHkWy/0rmyF6PXU+F2X/bh
+g9/4MYrNvSmT2wsYYOqZ1eqNNu5tFxsURldwJQ0WwVtzlK9sdnUuoksK5hQaFYMEDQrKDinIFaKAc3dinV3jRWYVnKNpVpKnDEv
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
NhGMS5/q7p4p8tocTFDczFoElZW2bO9unnfe5s/09ve/+Pa75178ng9c/JlPTjx5HsJAD9R5YqV3u1fsjY6yGh1l9X8+tGHpf/9T
78f//D19L8ypfMV552x43xln9a8kZa2aeTNnJk5UCk1E2o6R3ToK/zqkyFC3Y+vpn1xGCjFApIlTlZaX5ptraVL9eW6Whg1i16KD
enUKjjKMjIwkAPQVtTefXl+t1+Zm5pJSJSVAJ2C3MhA78KTSTEEl7rhVMejKfs35X5GiwmBo0qyhWav+vr6ZqenFGwBgbW2NgOio
0RMSxsfNgTyNrHljV1dXZs99oGKm0/oghE0bUPjwMhDezgvczMkTBimkecb15eXViw/sm3nh8PBw6YR9jdu9CDoieeIQDvKHxjYZ
sKxbCmx7rfMj0t1x7KFaBcG+LzRGAZGyWsBfrqAAcf/arnUCtuYCAwpg0sfYgTwxoS+44ILKrZNf+Wa12v33/X09WauVMZmkAjf2
HqdO+Ps9rx0mqJgF6ViU2zEb1yYcHp1b6dh+e0lRjNm8XUgzSBHX63U9ODCoEkpH/+MLH/9y8bFjBVpHlo79E7zjCIhbLD8vs6Ux
fDgbWEzk4UzQ9ZuGOc2+Uk63JWmyge1+lMMdLC+zSDq1Fk7ml+UeJOWADSdgryASqTQx/ydJKU2TUpIm5SRJykmq0iShVCWUqkSV
klSVEvuZpqqUpEmapon4T7l/E5UkSZKaP5UkifKfqfkUf6ZUmiRpKu+nKkn9n6k3TSlJ/J95VqXFP6XIfFqMVKLsX2oxTk1Zi29S
StIkUSkplYBIBXvF0sVhZtivNhYHb0f3g27u5ih4Qexd4QsgYmKdc6XaRV3V6vbh4eFug0jtSOjsIcOPkLEujRbrGSJQV7nvVXOL
/FSdJS3SbvdDkJVS4XencHuJ6n8HpkvCsg970AsGu2M+0lguGGSm1kAsXskUJ3+H580/VGSMkVGPQnl3zYoF+1yUio115K43yoUi
4+tiiz2HRcHO5CTfd/NceA1JGE94fEx1TO6EXqUB1qSThNNqhZcH+/kf//YvK7defTWXHq2ouoPx8Zo2e9f7Dqk8fV9/b1eLiRIg
yQHljUf/XxTFkIZ6/Emk7CuTTDvECgoJQzNTopPTTx9qXnjeti8M9vVeOTVfv/K9/3ThF7/+9acvtRvoJz6MjZEOhjuoVoN670d7
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
AABJRU5ErkJggg==
AIME_HEREDOC_EOF_9f2c

mkdir -p "public"
base64 -d > "public/logo-mark.png" << 'AIME_HEREDOC_EOF_9f2c'
iVBORw0KGgoAAAANSUhEUgAAAYAAAAGACAYAAACkx7W/AAEAAElEQVR4nOz9eZxmV1Uujj9rn/O+b41dXT2lOwMkgSTYAYXbTCLY
iaIEZPCi1SAo0YAdBEMug6Lgtbq+Kl6vXBVxuPQVFUduygFRkd8Hle7rhEhEkARIQhIy9jzUXO/7nr1+f+y91l77vJUQIEMPZ3VX
1fues8+ezjnPetbaa+8NNNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCON
NNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCON
NNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCON
NNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCON
NNJII4000kgjjTTSSCONNNJII4000kgjjTTSSCONNNJII408ZKHHugKNNHL6CX8d7w3xw1ePRhr5+qRRAI008mDCTNgD2gm4K64A
bj4MJ6duMr8H5XIAwPDF4B03AscnQbf/7Y2MHcDYpTt4y2+AZ2fBUSE0SqGRx0QaBdBIIxwZfQT6hXNBm1dudZdccgluvRVY/kZU
+6+k/sNd7NQNXGzfHN7B+2+5kb543w7eD3jMiEJorIVGHllpFEAjZ6cwE2bhpnBTMbI46jpPubDaNg+eWQPoN7/hc2Mv+C9btq5W
q8MdKr9h84bRSxeXq/bheT/a5zb1gcIzWux9QQUTqGBmcOGcJ9+vNo6g2jpZ8OJydcfddy5/bniitdRvr97/Z/9j9gBuu37VljV1
Axe4CUU0IKrZXfDhTKMMGnn4pVEAjZxFwrRzGsWWy9WNU83uokpPP/E9ne95+ysvmxgtn7S6gAnXaV3uytbWhcVqo2vR+UxFt1fR
hlbp13e73nfRalVMqDw7BgieHRzUocPOMeB52LEfbrMD01LfY6FdEreYF1oO9w+N4FDL9+8t4G+66fPH/uPvfvp3bgJmuiEDpqve
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
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

mkdir -p "src/app/api/chat"
cat > "src/app/api/chat/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { chatWithTools, type GeminiContent } from "@/lib/gemini";
import { ASSISTANT_TOOLS, ASSISTANT_SYSTEM_PROMPT, makeToolExecutor } from "@/lib/assistant-tools";

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });

  const messages = await prisma.chatMessage.findMany({
    where: { userId: (session.user as any).id },
    orderBy: { createdAt: "asc" },
    take: 100,
  });
  return NextResponse.json({ messages });
}

export async function POST(req: Request) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const userId = (session.user as any).id;

  const { message } = await req.json().catch(() => ({}));
  if (!message || typeof message !== "string" || !message.trim()) {
    return NextResponse.json({ error: "message is required" }, { status: 400 });
  }

  try {
    await prisma.chatMessage.create({ data: { userId, role: "user", content: message } });

    // Recent history gives Gemini context without resending the whole conversation forever.
    const recent = await prisma.chatMessage.findMany({
      where: { userId }, orderBy: { createdAt: "desc" }, take: 20,
    });
    const history: GeminiContent[] = recent.reverse().map((m) => ({
      role: m.role === "user" ? "user" : "model",
      parts: [{ text: m.content }],
    }));

    let reply: string;
    try {
      const result = await chatWithTools(history, ASSISTANT_TOOLS, makeToolExecutor(userId), ASSISTANT_SYSTEM_PROMPT);
      reply = result.reply;
    } catch (err: any) {
      reply = `Something went wrong talking to Gemini: ${err?.message || "unknown error"}`;
    }

    await prisma.chatMessage.create({ data: { userId, role: "model", content: reply } });
    return NextResponse.json({ reply });
  } catch (err: any) {
    // Most likely cause: the chat_message table doesn't exist yet because the
    // "add_chat" migration hasn't been run against this database.
    console.error("Chat route failed:", err);
    return NextResponse.json(
      { error: `Chat storage failed: ${err?.message || "unknown database error"}. Have you run 'npx prisma migrate dev --name add_chat'?` },
      { status: 500 }
    );
  }
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
  let matchedCount = 0;
  let notActionableCount = 0;
  let alreadyTrackedCount = 0;
  const notActionableSample: { subject: string; from: string }[] = [];

  for (const integration of integrations) {
    try {
      const gmail = await getGmailClient(integration);
      const messages = await listCandidateMessages(gmail);
      matchedCount += messages.length;

      for (const msg of messages) {
        // Already turned into a task on a previous run — skip without spending an AI call.
        const existing = await prisma.task.findUnique({
          where: { userId_sourceRef: { userId: integration.userId, sourceRef: msg.id } },
        });
        if (existing) { alreadyTrackedCount++; continue; }

        const text = `From: ${msg.from}\nSubject: ${msg.subject}\n\n${msg.bodyText || msg.snippet}`;
        const extracted = await extractTask("Gmail", text, msg.links);
        if (!extracted?.isActionable) {
          notActionableCount++;
          if (notActionableSample.length < 5) notActionableSample.push({ subject: msg.subject, from: msg.from });
          continue;
        }

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
            actionUrl: extracted.actionUrl ?? null,
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

  return NextResponse.json({
    ok: true,
    checked: integrations.length,
    candidateMessagesMatched: matchedCount,
    alreadyTracked: alreadyTrackedCount,
    judgedNotActionable: notActionableCount,
    tasksCreated: created,
    notActionableSample, // subjects the AI looked at but decided weren't worth a task — useful for tuning
  });
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/gmail/attachment"
cat > "src/app/api/gmail/attachment/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { getGmailClient, getAttachmentBytes } from "@/lib/gmail";

export async function GET(req: Request) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const userId = (session.user as any).id;

  const { searchParams } = new URL(req.url);
  const messageId = searchParams.get("messageId");
  const attachmentId = searchParams.get("attachmentId");
  const filename = (searchParams.get("filename") || "attachment").replace(/["\r\n]/g, "");
  const mimeType = searchParams.get("mimeType") || "application/octet-stream";

  if (!messageId || !attachmentId) {
    return NextResponse.json({ error: "messageId and attachmentId are required" }, { status: 400 });
  }

  const integration = await prisma.integration.findUnique({
    where: { userId_provider: { userId, provider: "google" } },
  });
  if (!integration) return NextResponse.json({ error: "Google isn't connected" }, { status: 400 });

  try {
    const gmail = await getGmailClient(integration);
    const bytes = await getAttachmentBytes(gmail, messageId, attachmentId);
    return new NextResponse(new Uint8Array(bytes), {
      headers: {
        "content-type": mimeType,
        "content-disposition": `inline; filename="${filename}"`,
        "content-length": String(bytes.length),
      },
    });
  } catch (err) {
    console.error("Failed to fetch attachment:", err);
    return NextResponse.json({ error: "Couldn't fetch the attachment — try reconnecting Google." }, { status: 500 });
  }
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

mkdir -p "src/app/api/tasks/[id]/attachments"
cat > "src/app/api/tasks/[id]/attachments/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { getGmailClient, listAttachments } from "@/lib/gmail";

export async function GET(_req: Request, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const userId = (session.user as any).id;

  const task = await prisma.task.findUnique({ where: { id: params.id } });
  if (!task || task.userId !== userId) return NextResponse.json({ error: "Not found" }, { status: 404 });
  if (task.source !== "gmail" || !task.sourceRef) return NextResponse.json({ attachments: [] });

  const integration = await prisma.integration.findUnique({
    where: { userId_provider: { userId, provider: "google" } },
  });
  if (!integration) return NextResponse.json({ attachments: [] });

  try {
    const gmail = await getGmailClient(integration);
    const attachments = await listAttachments(gmail, task.sourceRef);
    return NextResponse.json({ attachments });
  } catch (err) {
    console.error("Failed to list attachments:", err);
    return NextResponse.json({ attachments: [] });
  }
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/api/tasks"
cat > "src/app/api/tasks/route.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { getGmailClient, moveMessageOutOfInbox } from "@/lib/gmail";

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

  let inboxMoveError: string | null = null;
  if (status === "dismissed" && task.source === "gmail" && task.sourceRef) {
    try {
      const integration = await prisma.integration.findUnique({
        where: { userId_provider: { userId, provider: "google" } },
      });
      if (integration) {
        const gmail = await getGmailClient(integration);
        await moveMessageOutOfInbox(gmail, task.sourceRef);
        await prisma.activityEvent.create({
          data: { userId, text: `Moved the source email for "${task.title}" out of the inbox.`, kind: "automations" },
        });
      }
    } catch (err: any) {
      // Don't fail the dismiss over this — most likely cause is a token from before
      // gmail.modify was requested, which needs a Google reconnect to pick up.
      console.error("Failed to move dismissed task's source email:", err);
      inboxMoveError = "Task dismissed, but couldn't move the email — try reconnecting Google in Connections.";
    }
  }

  return NextResponse.json({ task: updated, inboxMoveError });
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

mkdir -p "src/app"
base64 -d > "src/app/apple-icon.png" << 'AIME_HEREDOC_EOF_9f2c'
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
oYeQcSk2sXEQeF9UqdIUS7Zy/M75yQuJiKXA4M4iY4X+JTI3N6d3L6o3DLgyo8EGTOSoOa9domQWANSwtRaYEBQKKQB2yscWbG20
plYcvdS5jOcZciQZACsQKXcOi3DeODNwmB2A+LkCZ4Ol0nRM9uy//MCBx7ZaZBtzjq25M8hYoZdJY451q0X2X/c8+YkLtvJHg35Z
ANASzBjiJYLSJc+XYVyBIvJeeFesuVh0IMCSQP0xPAYePkY4rl12rqFjyrktYAVHMywADdi+zdTevn41N5tq4zW3C8BXpYwVepls
vAZ86We5eqCvz+0ZrbVyIT5KldaKMlGwmk6ZbHT8xEIm9FyAAwhIOO6b8iE2YUXi3kNYfSgtBEhmgETJw4zh/0ruCLE2/bLs2sof
POfoVz+t1SLb5DtHaPxO8SVGJWKd//PnnZM7pvIYWxQlLHRKxVHAxz7sLA6c1y4COWW/jTWPcCRSc5wMAHEgOVFC/wgWNx6H0oec
RRJFAuzx/DT5LcQxBUEzuCi0WmJ6w1s/sWsaW+Xgq1vGCh2EaeM14Lmvcn1Pt/KqvnGUhrOAFGk6ThQEXsERmQUOCoqoWI459htR
otSJBQ2KmMKI1Mqng8rbdq/o8T3PaHg+HEB8LVccDs/aFGXRVfUTfrhv+vkOS69+fVj1I3JUIpzsKZd1T/1Fr3Z5b1AWSrHyukuB
6g0Wz0/vJNmZAFufgIQYBg+kGrGn2Agc8jRSBlneSAPcQl1E0jpchn/De6ghmJLK0Ds+HB7QjaMKLSul1tXtzfdZ1z/xbY3JnX7b
VYupV/2IHIkwU7sB+9LLdh2zu6Ne0xvAqgAfELCpRPc4wcphlre3dfRSOBCxNgdWwuuVhzFiYf3xwJ5QSWELh+M6626R5oJwsPYJ
XPH7s00suxA1FgqFNV3Ojr35gH4FiLixysPiq/riRyWNLVAg4r3l1Cu7XDleWVvAsiLr+GIFFaZuDYaCYFeGYuGNE5aCOcnFQOSJ
bTT2KnyIYVzN8IlFXo29A0qWXT6HP5dK9mMLkOe5ZR+X/yFwJ8HY4tCyLzInVt0laxa6+kUv/0Dvfu0tsKs5d3rVXviopNlk1W4r
84r39k9Y6KnnD3rGaLLaKwsxM7F1AQ5Y9hZVInnk6bX0fecoiuV2qMHT135bp1yKiRUHKx6wrz8XA2SH80JYjmXhOWyKAwfJ4AnY
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
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/chat"
cat > "src/app/chat/page.tsx" << 'AIME_HEREDOC_EOF_9f2c'
"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useLang } from "@/lib/i18n";

type Message = { id: string; role: "user" | "model"; content: string };

export default function ChatPage() {
  const { t } = useLang();
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState("");
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetch("/api/chat").then((r) => r.json()).then((d) => setMessages(d.messages ?? []));
  }, []);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, sending]);

  async function send(e: React.FormEvent, overrideText?: string) {
    e.preventDefault();
    const text = (overrideText ?? input).trim();
    if (!text || sending) return;
    setInput("");
    setError("");
    setMessages((m) => [...m, { id: "temp-" + Date.now(), role: "user", content: text }]);
    setSending(true);
    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ message: text }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || `Status ${res.status}`);
      setMessages((m) => [...m, { id: "reply-" + Date.now(), role: "model", content: data.reply }]);
    } catch (err: any) {
      setError(err?.message || "Couldn't reach the assistant.");
    } finally {
      setSending(false);
    }
  }

  const REFRESH_PROMPT =
    "Check my Gmail and Calendar right now for anything relevant — bills, invoices, deadlines, invitations, " +
    "appointments to confirm, and anything else worth tracking. Search thoroughly with several specific terms, not " +
    "just one broad search, and add anything actionable you find as a task. Then summarize what you found and what you added.";

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100vh" }}>
      <div className="topbar">
        <span className="brand"><img src="/logo-mark.png" alt="" /><b>AiMe</b></span>
        <div style={{ flex: 1 }} />
        <button
          className="btn"
          style={{ width: "auto" }}
          disabled={sending}
          onClick={(e) => send(e as any, REFRESH_PROMPT)}
        >
          🔄 {t("checkNow")}
        </button>
        <Link className="btn" style={{ width: "auto" }} href="/connections">{t("connections")}</Link>
        <Link className="btn" style={{ width: "auto" }} href="/dashboard">{t("today")}</Link>
      </div>

      <div style={{ flex: 1, overflowY: "auto", padding: "20px 16px" }}>
        <div style={{ maxWidth: 640, margin: "0 auto" }}>
          {messages.length === 0 && (
            <p style={{ color: "var(--text-2)", fontSize: 13.5 }}>{t("chatEmpty")}</p>
          )}
          {messages.map((m) => (
            <div
              key={m.id}
              style={{
                display: "flex",
                justifyContent: m.role === "user" ? "flex-end" : "flex-start",
                marginBottom: 10,
              }}
            >
              <div
                style={{
                  maxWidth: "80%",
                  padding: "9px 13px",
                  borderRadius: 12,
                  fontSize: 14,
                  whiteSpace: "pre-wrap",
                  background: m.role === "user" ? "var(--accent)" : "var(--surface-2)",
                  color: m.role === "user" ? "#fff" : "var(--text)",
                  border: m.role === "user" ? "none" : "1px solid var(--border)",
                }}
              >
                {m.content}
              </div>
            </div>
          ))}
          {sending && <p style={{ color: "var(--text-2)", fontSize: 13 }}>{t("thinking")}</p>}
          {error && <div className="error">{error}</div>}
          <div ref={bottomRef} />
        </div>
      </div>

      <form onSubmit={send} style={{ borderTop: "1px solid var(--border)", padding: 14, display: "flex", gap: 8, maxWidth: 640, margin: "0 auto", width: "100%" }}>
        <input
          className="input"
          style={{ flex: 1 }}
          placeholder={t("askPlaceholder")}
          value={input}
          onChange={(e) => setInput(e.target.value)}
        />
        <button className="btn primary" style={{ width: "auto" }} disabled={sending}>{t("send")}</button>
      </form>
    </div>
  );
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/connections"
cat > "src/app/connections/connections-client.tsx" << 'AIME_HEREDOC_EOF_9f2c'
"use client";
import { useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { useLang } from "@/lib/i18n";

type Status = { integrations: { provider: string; status: string; accountLabel?: string }[] };

export default function ConnectionsClient() {
  const params = useSearchParams();
  const { t, lang, setLang } = useLang();
  const [status, setStatus] = useState<Status>({ integrations: [] });
  const [telegram, setTelegram] = useState<{ code: string; deepLink: string | null } | null>(null);
  const [level, setLevel] = useState<"gentle" | "balanced" | "proactive" | null>(null);
  const [connectError, setConnectError] = useState<string | null>(null);

  async function refresh() {
    const res = await fetch("/api/integrations/status");
    if (res.ok) setStatus(await res.json());
  }

  useEffect(() => {
    refresh();
    if (params.get("error")) {
      setConnectError(params.get("detail") || `Connecting ${params.get("error")} failed. Check Vercel's Runtime Logs for details.`);
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const isConnected = (provider: string) =>
    status.integrations.some((i) => i.provider === provider && i.status === "connected");
  const labelFor = (provider: string) =>
    status.integrations.find((i) => i.provider === provider)?.accountLabel;

  async function startTelegram() {
    const res = await fetch("/api/integrations/telegram/connect");
    const data = await res.json();
    setTelegram(data);
    const interval = setInterval(async () => {
      const r = await fetch("/api/integrations/telegram/status");
      const d = await r.json();
      if (d.connected) { clearInterval(interval); refresh(); }
    }, 2000);
    setTimeout(() => clearInterval(interval), 180000);
  }

  async function saveLevel(l: "gentle" | "balanced" | "proactive") {
    setLevel(l);
    await fetch("/api/user/proactivity", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ level: l }),
    });
  }

  return (
    <div>
      <div className="topbar">
        <span className="brand"><img src="/logo-mark.png" alt="" /><b>AiMe</b></span>
        <div style={{ flex: 1 }} />
        <Link className="btn" style={{ width: "auto" }} href="/dashboard">{t("today")}</Link>
      </div>
      <div className="content">
        <h1 style={{ fontSize: 26, letterSpacing: "-.02em" }}>{t("connectionsTitle")}</h1>
        <p style={{ color: "var(--text-2)" }}>{t("connectionsLead")}</p>
        {connectError && <div className="error">{connectError}</div>}

        <div className="conn-row">
          <div className="grow"><b>{t("language")}</b><small>English / עברית</small></div>
          <div className="seg">
            <button className={lang === "en" ? "on" : ""} onClick={() => setLang("en")}>English</button>
            <button className={lang === "he" ? "on" : ""} onClick={() => setLang("he")}>עברית</button>
          </div>
        </div>

        <div className="conn-row">
          <span className="logo">✉️</span>
          <div className="grow">
            <b>Gmail, Calendar &amp; Drive</b>
            <small>{isConnected("google") ? labelFor("google") : "Read-only, except adding an event when you click \"Add to calendar\""}</small>
          </div>
          {isConnected("google") ? (
            <span className="pill green">Connected</span>
          ) : (
            <a className="btn primary" style={{ width: "auto" }} href="/api/integrations/google/connect">Connect</a>
          )}
        </div>

        <div className="conn-row">
          <span className="logo">💬</span>
          <div className="grow">
            <b>Telegram</b>
            <small>Stands in for WhatsApp — message the bot directly to create tasks</small>
          </div>
          {isConnected("telegram") ? (
            <span className="pill green">Connected</span>
          ) : (
            <button className="btn primary" style={{ width: "auto" }} onClick={startTelegram}>Connect</button>
          )}
        </div>
        {telegram && !isConnected("telegram") && (
          <div style={{ marginTop: -4, marginBottom: 16 }}>
            {telegram.deepLink && (
              <a className="btn" href={telegram.deepLink} target="_blank" rel="noreferrer">Open Telegram &amp; link automatically</a>
            )}
            <div className="code-box" style={{ marginTop: 10 }}>/start {telegram.code}</div>
          </div>
        )}

        <div className="conn-row">
          <span className="logo">💼</span>
          <div className="grow"><b>Slack</b><small>{isConnected("slack") ? labelFor("slack") : "Surface work messages waiting on a reply"}</small></div>
          {isConnected("slack") ? <span className="pill green">Connected</span> :
            <a className="btn" style={{ width: "auto" }} href="/api/integrations/slack/connect">Connect</a>}
        </div>

        <div className="conn-row">
          <span className="logo">📄</span>
          <div className="grow"><b>Notion</b><small>{isConnected("notion") ? labelFor("notion") : "File invoices and receipts automatically"}</small></div>
          {isConnected("notion") ? <span className="pill green">Connected</span> :
            <a className="btn" style={{ width: "auto" }} href="/api/integrations/notion/connect">Connect</a>}
        </div>

        <div className="conn-row" style={{ opacity: 0.6 }}>
          <span className="logo">📱</span>
          <div className="grow"><b>WhatsApp</b><small>Not available — no personal-account API exists</small></div>
          <span className="pill">Unavailable</span>
        </div>

        <h2 style={{ fontSize: 16, marginTop: 28 }}>{t("proactivityTitle")}</h2>
        {([
          ["gentle", "Gentle", "Only notify me when something is important."],
          ["balanced", "Balanced", "Suggest actions and reminders."],
          ["proactive", "Proactive", "Take care of routine things automatically, within limits I set."],
        ] as const).map(([id, label, desc]) => (
          <div key={id} className="conn-row" style={{ cursor: "pointer" }} onClick={() => saveLevel(id)}>
            <div className="grow"><b>{label}</b><small>{desc}</small></div>
            {level === id && <span className="pill green">Saved</span>}
          </div>
        ))}
      </div>
    </div>
  );
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/connections"
cat > "src/app/connections/page.tsx" << 'AIME_HEREDOC_EOF_9f2c'
import { Suspense } from "react";
import ConnectionsClient from "./connections-client";

export default function ConnectionsPage() {
  return (
    <Suspense fallback={null}>
      <ConnectionsClient />
    </Suspense>
  );
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/dashboard"
cat > "src/app/dashboard/page.tsx" << 'AIME_HEREDOC_EOF_9f2c'
"use client";
import { useEffect, useState } from "react";
import { useSession, signOut } from "next-auth/react";
import Link from "next/link";
import { useLang } from "@/lib/i18n";

type Task = {
  id: string; title: string; type: string; source: string; priority: string; status: string;
  category: string; due: string | null; amount: number | null; currency: string | null;
  aiSummary: string | null; why: string | null; sourceRef: string | null; actionUrl: string | null;
  createdAt: string; user: { name: string };
};

type Attachment = { attachmentId: string; filename: string; mimeType: string; size?: number };

const TYPE_ICON: Record<string, string> = { bill: "💳", appointment: "📅", document: "📄", message: "💬", task: "✅" };
const PRIORITY_RANK: Record<string, number> = { urgent: 0, high: 1, normal: 2, low: 3 };
const STALE_DAYS = 5;

function daysBetween(a: Date, b: Date) {
  return Math.round((a.getTime() - b.getTime()) / 86400000);
}

// Priority first, then soonest due date, then oldest-created — so something urgent
// today outranks something normal next week, and among equals, what's been
// waiting longest surfaces first rather than getting buried by newer arrivals.
function smartSort(tasks: Task[]): Task[] {
  return [...tasks].sort((a, b) => {
    const pr = (PRIORITY_RANK[a.priority] ?? 9) - (PRIORITY_RANK[b.priority] ?? 9);
    if (pr !== 0) return pr;
    const ad = a.due ? new Date(a.due).getTime() : Infinity;
    const bd = b.due ? new Date(b.due).getTime() : Infinity;
    if (ad !== bd) return ad - bd;
    return new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime();
  });
}

function urgencyBadge(t: Task, tt: (k: any) => string): { label: string; tone: "red" | "amber" } | null {
  const now = new Date();
  if (t.due) {
    const due = new Date(t.due);
    const diff = daysBetween(new Date(due.toDateString()), new Date(now.toDateString()));
    if (diff < 0) return { label: tt("overdue"), tone: "red" };
    if (diff === 0) return { label: tt("dueToday"), tone: "red" };
    if (diff === 1) return { label: tt("dueTomorrow"), tone: "amber" };
  }
  if (daysBetween(now, new Date(t.createdAt)) >= STALE_DAYS) {
    return { label: tt("sittingAWhile"), tone: "amber" };
  }
  return null;
}

function gmailLink(sourceRef: string) {
  return `https://mail.google.com/mail/u/0/#all/${sourceRef}`;
}

function attachmentUrl(messageId: string, a: Attachment) {
  const params = new URLSearchParams({
    messageId, attachmentId: a.attachmentId, filename: a.filename, mimeType: a.mimeType,
  });
  return `/api/gmail/attachment?${params.toString()}`;
}

export default function Dashboard() {
  const { data: session } = useSession();
  const { t } = useLang();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [notice, setNotice] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [attachments, setAttachments] = useState<Record<string, Attachment[] | "loading">>({});

  async function load() {
    setLoading(true);
    const res = await fetch("/api/tasks");
    const data = await res.json();
    setTasks(data.tasks ?? []);
    setLoading(false);
  }

  useEffect(() => { load(); }, []);

  async function toggleExpand(tk: Task) {
    const next = expanded === tk.id ? null : tk.id;
    setExpanded(next);
    if (next && tk.source === "gmail" && !attachments[tk.id]) {
      setAttachments((a) => ({ ...a, [tk.id]: "loading" }));
      const res = await fetch(`/api/tasks/${tk.id}/attachments`);
      const data = await res.json().catch(() => ({ attachments: [] }));
      setAttachments((a) => ({ ...a, [tk.id]: data.attachments ?? [] }));
    }
  }

  async function complete(id: string) {
    await fetch("/api/tasks", {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id, status: "completed" }),
    });
    load();
  }

  async function dismiss(id: string) {
    const res = await fetch("/api/tasks", {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id, status: "dismissed" }),
    });
    const data = await res.json().catch(() => ({}));
    if (data?.inboxMoveError) setNotice(data.inboxMoveError);
    load();
  }

  const open = smartSort(tasks.filter((tk) => tk.status !== "completed"));
  const done = tasks.filter((tk) => tk.status === "completed");

  return (
    <div>
      <div className="topbar">
        <span className="brand"><img src="/logo-mark.png" alt="" /><b>AiMe</b></span>
        <span style={{ color: "var(--text-2)", fontSize: 13 }}>{session?.user?.name}</span>
        <div style={{ flex: 1 }} />
        <Link className="btn" style={{ width: "auto" }} href="/chat">{t("chat")}</Link>
        <Link className="btn" style={{ width: "auto" }} href="/connections">{t("connections")}</Link>
        <Link className="btn" style={{ width: "auto" }} href="/household">{t("account")}</Link>
        <button className="btn" style={{ width: "auto" }} onClick={() => signOut({ callbackUrl: "/login" })}>{t("signOut")}</button>
      </div>
      <div className="content" style={{ maxWidth: 1080 }}>
        <h1 style={{ fontSize: 26, letterSpacing: "-.02em" }}>{t("today")}</h1>
        {notice && <div className="error">{notice}</div>}

        {loading ? (
          <p style={{ color: "var(--text-2)" }}>{t("loading")}</p>
        ) : open.length === 0 ? (
          <p style={{ color: "var(--text-2)" }}>
            Nothing here yet. Connected accounts sync automatically every 15 minutes — or trigger the cron
            endpoint manually while testing.
          </p>
        ) : (
          <div className="grid2">
            {open.map((tk) => {
              const badge = urgencyBadge(tk, t);
              const isOpen = expanded === tk.id;
              const atts = attachments[tk.id];
              return (
                <div className={`tcard${tk.priority === "urgent" ? " urgent" : ""}`} key={tk.id}>
                  <div className="top">
                    <span className={`tico ${tk.type}`}>{TYPE_ICON[tk.type] ?? "✅"}</span>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <h3>{tk.title}</h3>
                      <div className="meta">
                        <span className={`pri ${tk.priority}`} title={tk.priority} />
                        <span>{tk.source}</span>
                        {badge && <span className={`pill ${badge.tone}`}>{badge.label}</span>}
                      </div>
                    </div>
                  </div>

                  {tk.type === "bill" && tk.amount != null && (
                    <div className="amount">{tk.currency ?? ""}{tk.amount}</div>
                  )}

                  {(tk.aiSummary || tk.why) && <p className="why">{tk.aiSummary ?? tk.why}</p>}

                  <div className="foot">
                    {tk.actionUrl && (
                      <a className="btn primary" style={{ width: "auto" }} href={tk.actionUrl} target="_blank" rel="noreferrer">
                        {tk.type === "bill" ? "Pay now" : t("openEmail")}
                      </a>
                    )}
                    {tk.source === "gmail" && tk.sourceRef && (
                      <a className="btn" style={{ width: "auto" }} href={gmailLink(tk.sourceRef)} target="_blank" rel="noreferrer">
                        {t("openEmail")}
                      </a>
                    )}
                    <button className="btn" style={{ width: "auto" }} onClick={() => complete(tk.id)}>{t("complete")}</button>
                    <button className="btn" style={{ width: "auto" }} onClick={() => dismiss(tk.id)}>{t("dismiss")}</button>
                    <button className="tcard-toggle" onClick={() => toggleExpand(tk)}>
                      {isOpen ? "▲ Less" : "▼ Details"}
                    </button>
                  </div>

                  {isOpen && (
                    <div className="tcard-details">
                      <dl>
                        <dt>Category</dt><dd>{tk.category}</dd>
                        <dt>Priority</dt><dd>{tk.priority}</dd>
                        {tk.due && <><dt>Due</dt><dd>{new Date(tk.due).toLocaleDateString()}</dd></>}
                        <dt>Detected</dt><dd>{new Date(tk.createdAt).toLocaleString()}</dd>
                        <dt>Source</dt><dd>{tk.source}</dd>
                        {tk.why && <><dt>Why</dt><dd>{tk.why}</dd></>}
                      </dl>
                      {tk.source === "gmail" && tk.sourceRef && (
                        <div>
                          {atts === "loading" && <p style={{ fontSize: 12.5, color: "var(--text-2)", margin: 0 }}>Checking for attachments…</p>}
                          {Array.isArray(atts) && atts.length === 0 && (
                            <p style={{ fontSize: 12.5, color: "var(--text-2)", margin: 0 }}>No attachments on this email.</p>
                          )}
                          {Array.isArray(atts) && atts.length > 0 && (
                            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
                              {atts.map((a) => (
                                <a key={a.attachmentId} className="attach-item" href={attachmentUrl(tk.sourceRef as string, a)} target="_blank" rel="noreferrer">
                                  📎 <span>{a.filename}</span>
                                </a>
                              ))}
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}

        {done.length > 0 && (
          <>
            <h2 style={{ fontSize: 15, marginTop: 28, color: "var(--text-2)" }}>{t("completed")}</h2>
            {done.map((tk) => (
              <div className="row" key={tk.id} style={{ opacity: 0.6 }}>
                <div className="t"><b style={{ textDecoration: "line-through" }}>{tk.title}</b></div>
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
base64 -d > "src/app/favicon.ico" << 'AIME_HEREDOC_EOF_9f2c'
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
KQAAoNlkqtdNbvqGf9rVwvtE0pMZaXPgfNWcr8BrxaX/1Wrn6r960q+pw+REnQfKoAHA3Q/woPfhpmot/e1sfxctz88gvaEGALev
aJ9to/L2TgHJMttx1nv9xlVNduqwWRXt7GT6SXtSUq+bzBSNoWm+n56s5Llpfaa/ZmeQWVFVr5uURQq0ALRaSKc8Wm/IG/Lzkf8H
FZTbOc7j4aUAAAAASUVORK5CYIKJUE5HDQoaCgAAAA1JSERSAAABAAAAAQAIBgAAAFxyqGYAAIhoSURBVHic7b15gBxHdT/+eVXd
c+ypWz6wjQEHkAnfJOZMAiuTOxBCCKMQQiBcMgZsY4yNwfAbDYTTmNsYKdyQEHZDEsjJkdhLyEGCSTgsbhufkiVLWu3u7Fzd9X5/
VL2q6pEAA/Zqtepnr2amu7q6+njvfd5Rr4CSSiqppJJKKqmkkkoqqaSSSiqppJJKKqmkkkoqqaSSSiqppJJKKqmkkkoqqaSSSiqp
pJJKKqmkkkoqqaSSSiqppJJKKqmkkkoqqaSSSiqppJJKKqmkkkoqqaSSSiqppJJKKqmkkkoqqaSSSiqppJJKKqmkkkoqqaSSSiqp
pJJKKqmkkkoqqaSSSirppyE61gMoaYUTMzV33L33pNUCA8T39pBKuueoFAAlOWJqNkG7zwbdeAhq7A7wprPBM9sov/tdsJraAfXA
U66nQ2vPMVtuALdaZO7FQZf0U1IpAE5UYqYGoPbtAFlGVzlwpPJu/vntG3rV0Ylv39bXGZPKKlWV99qK6qOsDHiU2PzsKUDnQPvg
f3x456HZ2VY2dCJCE7pxNrgUCCuPSgFwglGzyWrPKdC7zqOBbGNm9Sdv+7+J5NTTfqZ/GPfhav2MpR6fDk0bSOFMbczmhYFOMqNV
bkxKBAUAhpTRZPL1dUZucHvGdOeI4r31EXXTaDK47a79h77ypLXz3/qDbQ/pi2iZupYTXAfM7kAOKs2FY02lADgBiJlp63XQs+8G
Y8ZC+u07b9+QVSs/myXJVmDkEUs9nJERb14YYDSjatUoAAxwzmCTg0iBGSCwAwoMVgps+0eSaugE0AAUAJ318zRVB8ar5hZtsi8P
+tmnzj698s1X/Ur9ezKuqea1yaazt/54ZkZJ9yiVAmBVE9M5O5Fc77Q9M6sXfXzu56CqT5jr4PFtTn6+k6dpn4HeADBZzqw4h0EO
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
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app"
cat > "src/app/globals.css" << 'AIME_HEREDOC_EOF_9f2c'
:root{
  --bg:#F6F5F3; --surface:#FFFFFF; --surface-2:#FAF9F7; --border:#E6E2DD; --border-2:#D6D1C9;
  --text:#23211F; --text-2:#6B6660; --text-3:#9A958E;
  --accent:#0E7C86; --accent-2:#0A616A; --accent-weak:#E2F0F1; --accent-line:#BEDFE1;
  --red:#B03A2C; --red-weak:#FBEAE6; --green:#2C7357; --green-weak:#E3F0E9;
  --amber:#9C6511; --amber-weak:#FBF0DC;
  --sans:'Alef',ui-sans-serif,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font-family:var(--sans);font-size:14px;line-height:1.5}
a{color:var(--accent)}
button,input{font:inherit}

/* RTL support: flipped automatically whenever <html dir="rtl"> is set by the language toggle. */
html[dir="rtl"] body{text-align:right}
html[dir="rtl"] .topbar,
html[dir="rtl"] .conn-row,
html[dir="rtl"] .row,
html[dir="rtl"] .list-item,
html[dir="rtl"] .setrow{flex-direction:row-reverse}
html[dir="rtl"] .seg{flex-direction:row-reverse}
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
.brand{display:inline-flex;align-items:center;gap:8px}
.brand img{height:22px;width:auto;display:block}
.brand-hero{height:34px;width:auto;display:block;margin-bottom:14px}
.content{max-width:860px;margin:0 auto;padding:28px 20px 60px}
.row{display:flex;gap:12px;align-items:center;padding:12px 14px;border:1px solid var(--border);border-radius:10px;background:var(--surface);margin-bottom:8px}
.row .t{flex:1;min-width:0}
.row .t b{display:block;font-size:14px}
.row .t small{color:var(--text-2);font-size:12.5px}

/* ---------- task cards ---------- */
.grid2{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:12px;margin-top:8px}
.tcard{
  background:var(--surface);border:1px solid var(--border);border-radius:11px;padding:14px 15px;
  display:flex;flex-direction:column;gap:10px;position:relative;
}
.tcard.urgent{border-color:var(--red);box-shadow:0 0 0 1px var(--red)}
.tcard .top{display:flex;gap:10px;align-items:flex-start}
.tico{width:30px;height:30px;border-radius:8px;display:grid;place-items:center;flex:none;font-size:15px}
.tico.bill{background:var(--red-weak)}
.tico.message{background:var(--green-weak)}
.tico.document{background:var(--accent-weak)}
.tico.appointment{background:var(--amber-weak)}
.tico.task{background:var(--surface-2)}
.tcard h3{margin:0;font-size:15px;font-weight:600;letter-spacing:-.01em}
.tcard .meta{display:flex;align-items:center;gap:7px;margin-top:3px;flex-wrap:wrap;font-size:11.5px;color:var(--text-3)}
.tcard .why{font-size:12.8px;color:var(--text-2);margin:0;padding-left:10px;border-left:2px solid var(--border)}
html[dir="rtl"] .tcard .why{padding-left:0;border-left:none;padding-right:10px;border-right:2px solid var(--border)}
.amount{font-size:20px;font-weight:600;letter-spacing:-.02em;font-variant-numeric:tabular-nums}
.tcard .foot{display:flex;align-items:center;gap:8px;margin-top:auto}
.pri{width:7px;height:7px;border-radius:50%;flex:none;background:var(--text-3);display:inline-block}
.pri.urgent{background:var(--red)} .pri.high{background:var(--amber)}
.pri.normal{background:var(--accent)} .pri.low{background:var(--text-3)}
.pill.red{background:var(--red-weak);color:var(--red)}
.pill.amber{background:var(--amber-weak);color:var(--amber)}
.tcard-toggle{background:none;border:none;color:var(--text-2);font-size:12px;cursor:pointer;margin-left:auto;padding:4px 2px}
html[dir="rtl"] .tcard-toggle{margin-left:0;margin-right:auto}
.tcard-details{border-top:1px solid var(--border);margin-top:2px;padding-top:10px;display:flex;flex-direction:column;gap:8px}
.tcard-details dl{display:grid;grid-template-columns:88px 1fr;gap:5px 10px;font-size:12.5px;margin:0}
.tcard-details dt{color:var(--text-3)}
.tcard-details dd{margin:0;color:var(--text)}
.attach-item{display:flex;align-items:center;gap:8px;border:1px solid var(--border);border-radius:8px;padding:7px 9px;font-size:12.5px}
.attach-item span{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/app/household"
cat > "src/app/household/page.tsx" << 'AIME_HEREDOC_EOF_9f2c'
"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useLang } from "@/lib/i18n";

type Household = { name: string; inviteCode: string; members: { id: string; name: string; email: string; role: string }[] };

export default function HouseholdPage() {
  const { t } = useLang();
  const [household, setHousehold] = useState<Household | null>(null);

  useEffect(() => {
    fetch("/api/household").then((r) => r.json()).then((d) => setHousehold(d.household));
  }, []);

  return (
    <div>
      <div className="topbar">
        <span className="brand"><img src="/logo-mark.png" alt="" /><b>AiMe</b></span>
        <div style={{ flex: 1 }} />
        <Link className="btn" style={{ width: "auto" }} href="/connections">{t("connections")}</Link>
        <Link className="btn" style={{ width: "auto" }} href="/dashboard">{t("backToToday")}</Link>
      </div>
      <div className="content">
        <h1 style={{ fontSize: 26, letterSpacing: "-.02em" }}>{t("accountTitle")}</h1>
        {household && (
          <>
            <p style={{ color: "var(--text-2)" }}>
              {household.members.length > 1
                ? "Everyone below shares this account, each with their own login and their own connected services."
                : "It's just you here — nothing else to set up. If you ever want to share this with a partner or family member, send them this code:"}
            </p>
            <div className="code-box" style={{ marginBottom: 8 }}>{household.inviteCode}</div>
            <p style={{ color: "var(--text-3)", fontSize: 12.5, marginTop: 0, marginBottom: 20 }}>
              They'll sign up and choose "Join someone else's," using this code.
            </p>
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
import FloatingChat from "@/components/FloatingChat";

export const metadata = {
  title: "AiMe",
  icons: {
    icon: "/favicon.ico",
    apple: "/apple-icon.png",
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link href="https://fonts.googleapis.com/css2?family=Alef:wght@400;700&display=swap" rel="stylesheet" />
      </head>
      <body>
        <Providers>
          {children}
          <FloatingChat />
        </Providers>
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
    try {
      const res = await signIn("credentials", { email, password, redirect: false });
      if (res?.error) setError("That email and password don't match.");
      else router.push("/dashboard");
    } catch {
      setError("Couldn't reach the server. Check your connection and try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="shell">
      <form className="panel" onSubmit={submit}>
        <img src="/logo-full.png" alt="AiMe" className="brand-hero" />
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

  const [connectError, setConnectError] = useState<string | null>(null);

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
    if (params.get("error")) {
      setConnectError(params.get("detail") || `Connecting ${params.get("error")} failed. Check Vercel's Runtime Logs for details.`);
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
      <img src="/logo-mark.png" alt="" className="brand-hero" style={{ height: 44 }} />
      <h1>Meet AiMe</h1>
      <p className="lead">Your digital life is full of information. AiMe turns it into action — bills, replies, appointments, the small things that fall through the cracks.</p>
      {household && (
        <div className="conn-row">
          <span className="logo">🔗</span>
          <div className="grow">
            <b>Want to share this with someone?</b>
            <small>They can join anytime with this code — no rush: <code>{household.inviteCode}</code></small>
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
        {connectError && <div className="error" style={{ marginBottom: 16 }}>{connectError}</div>}
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
    try {
      const res = await fetch("/api/signup", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ mode, name, email, password, householdName, inviteCode }),
      });

      let data: any = {};
      try {
        data = await res.json();
      } catch {
        // Server returned something that wasn't JSON (e.g. a crash page) — treat as a generic failure.
        throw new Error(`Server returned an unexpected response (status ${res.status}).`);
      }

      if (!res.ok) {
        setError(data.error || `Something went wrong (status ${res.status}).`);
        return;
      }

      await signIn("credentials", { email, password, redirect: false });
      router.push("/onboarding");
    } catch (err: any) {
      setError(err?.message || "Couldn't reach the server. Check your connection and try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="shell">
      <form className="panel" onSubmit={submit}>
        <img src="/logo-full.png" alt="AiMe" className="brand-hero" />
        <h1>Create your account</h1>
        <p className="lead">Set this up just for yourself, or share it with a partner or family member — either way works.</p>
        {error && <div className="error">{error}</div>}
        <div className="seg">
          <button type="button" className={mode === "create" ? "on" : ""} onClick={() => setMode("create")}>Create my account</button>
          <button type="button" className={mode === "join" ? "on" : ""} onClick={() => setMode("join")}>Join someone else's</button>
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
            <label>Name for this account (optional)</label>
            <input className="input" value={householdName} onChange={(e) => setHouseholdName(e.target.value)} placeholder={`e.g. "${name || "Alex"}" or "The Cohens" — only needed if you'll invite someone`} />
          </div>
        ) : (
          <div className="field">
            <label>Invite code from whoever set this up</label>
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

mkdir -p "src/components"
cat > "src/components/FloatingChat.tsx" << 'AIME_HEREDOC_EOF_9f2c'
"use client";
import { useEffect, useRef, useState } from "react";
import { useSession } from "next-auth/react";
import { usePathname } from "next/navigation";
import Link from "next/link";
import { useAssistantChat } from "@/lib/useAssistantChat";
import { useLang } from "@/lib/i18n";

const REFRESH_PROMPT =
  "Check my Gmail and Calendar right now for anything relevant — bills, invoices, deadlines, invitations, appointments " +
  "to confirm, and anything else worth tracking. Search thoroughly with several specific terms, not just one broad " +
  "search, and add anything actionable you find as a task. Then summarize what you found and what you added.";

export default function FloatingChat() {
  const { status } = useSession();
  const pathname = usePathname();
  const { t } = useLang();
  const [open, setOpen] = useState(false);
  const [input, setInput] = useState("");
  const { messages, sending, error, send } = useAssistantChat(open);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (open) bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, sending, open]);

  // Don't render pre-login, and don't double up with the full /chat page.
  if (status !== "authenticated" || pathname === "/chat") return null;

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!input.trim()) return;
    send(input);
    setInput("");
  }

  return (
    <>
      <button
        onClick={() => setOpen((o) => !o)}
        aria-label={open ? "Close AiMe chat" : "Open AiMe chat"}
        style={{
          position: "fixed", bottom: 20, right: 20, width: 52, height: 52, borderRadius: "50%",
          background: "var(--accent)", color: "#fff", border: "none", cursor: "pointer",
          boxShadow: "0 8px 24px rgba(0,0,0,.25)", zIndex: 200, display: "grid", placeItems: "center",
          fontSize: 22, lineHeight: 1,
        }}
      >
        {open ? "×" : "💬"}
      </button>

      {open && (
        <div
          style={{
            position: "fixed", bottom: 84, right: 20, width: 340, maxWidth: "calc(100vw - 24px)",
            height: 460, maxHeight: "calc(100vh - 120px)", background: "var(--surface)",
            border: "1px solid var(--border)", borderRadius: 14, boxShadow: "0 20px 50px rgba(0,0,0,.28)",
            zIndex: 199, display: "flex", flexDirection: "column", overflow: "hidden",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "10px 12px", borderBottom: "1px solid var(--border)" }}>
            <img src="/logo-mark.png" alt="" style={{ width: 20, height: 20 }} />
            <b style={{ fontSize: 13.5 }}>AiMe</b>
            <div style={{ flex: 1 }} />
            <button
              onClick={() => send(REFRESH_PROMPT)}
              disabled={sending}
              title="Check email & calendar now"
              style={{ background: "none", border: "none", cursor: "pointer", fontSize: 15, padding: 4 }}
            >
              🔄
            </button>
            <Link href="/chat" style={{ fontSize: 12, color: "var(--accent)" }}>{t("expand")}</Link>
          </div>

          <div style={{ flex: 1, overflowY: "auto", padding: 12 }}>
            {messages.length === 0 && (
              <p style={{ color: "var(--text-2)", fontSize: 12.5, margin: 0 }}>
                Ask about bills, your calendar, or recent activity.
              </p>
            )}
            {messages.map((m) => (
              <div key={m.id} style={{ display: "flex", justifyContent: m.role === "user" ? "flex-end" : "flex-start", marginBottom: 8 }}>
                <div
                  style={{
                    maxWidth: "85%", padding: "7px 10px", borderRadius: 10, fontSize: 13, whiteSpace: "pre-wrap",
                    background: m.role === "user" ? "var(--accent)" : "var(--surface-2)",
                    color: m.role === "user" ? "#fff" : "var(--text)",
                    border: m.role === "user" ? "none" : "1px solid var(--border)",
                  }}
                >
                  {m.content}
                </div>
              </div>
            ))}
            {sending && <p style={{ color: "var(--text-2)", fontSize: 12 }}>{t("thinking")}</p>}
            {error && <div className="error" style={{ fontSize: 12 }}>{error}</div>}
            <div ref={bottomRef} />
          </div>

          <form onSubmit={submit} style={{ display: "flex", gap: 6, padding: 10, borderTop: "1px solid var(--border)" }}>
            <input
              className="input"
              style={{ flex: 1, height: 32, fontSize: 13 }}
              placeholder={t("askShort")}
              value={input}
              onChange={(e) => setInput(e.target.value)}
            />
            <button className="btn primary" style={{ width: "auto", height: 32, fontSize: 13, padding: "0 10px" }} disabled={sending}>
              {t("send")}
            </button>
          </form>
        </div>
      )}
    </>
  );
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/lib"
cat > "src/lib/assistant-tools.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { prisma } from "./db";
import { getGmailClient, getCalendarClient, getMessageDetails } from "./gmail";
import type { ToolDeclaration } from "./gemini";

// Every executor here is scoped to a single userId and is read-only — nothing in this
// file sends an email, creates a calendar event, or changes a task's status. That
// mirrors the rest of the app's rule that AI never takes a high-impact action silently.

export const ASSISTANT_TOOLS: ToolDeclaration[] = [
  {
    name: "search_tasks",
    description: "Search the person's AiMe tasks (bills, reminders, appointments, things waiting on someone).",
    parameters: {
      type: "object",
      properties: {
        status: { type: "string", enum: ["open", "waiting", "completed", "dismissed", "any"], description: "Filter by status, or 'any' for all." },
        query: { type: "string", description: "Optional text to match against the task title." },
      },
    },
  },
  {
    name: "search_gmail",
    description: "Search the person's Gmail. Use Gmail search syntax if helpful (e.g. 'from:amazon', 'newer_than:7d').",
    parameters: {
      type: "object",
      properties: {
        query: { type: "string", description: "Gmail search query." },
        maxResults: { type: "string", description: "Max messages to return, default 5." },
      },
      required: ["query"],
    },
  },
  {
    name: "search_calendar",
    description: "List the person's upcoming Google Calendar events in a date range.",
    parameters: {
      type: "object",
      properties: {
        daysAhead: { type: "string", description: "How many days ahead to look, default 7." },
      },
    },
  },
  {
    name: "get_recent_activity",
    description: "See what AiMe has recently found or done automatically for this person.",
    parameters: {
      type: "object",
      properties: {
        limit: { type: "string", description: "Max items, default 10." },
      },
    },
  },
  {
    name: "get_email_details",
    description:
      "Get the full body and any real links found in one specific email, by its Gmail message id (from a " +
      "search_gmail result). Use this on a bill before create_task, to find the actual payment link — never " +
      "invent a URL, only ever use one returned by this tool.",
    parameters: {
      type: "object",
      properties: {
        messageId: { type: "string", description: "The Gmail message id, from search_gmail results." },
      },
      required: ["messageId"],
    },
  },
  {
    name: "create_task",
    description:
      "Add a bill or an important message to the person's Today list, the same way AiMe's automatic background " +
      "check already does. Check search_tasks first so you don't create a duplicate of something already tracked. " +
      "If this came from a specific Gmail message, pass its id as sourceRef so it lines up with the background " +
      "sync and never gets created twice. For bills, call get_email_details first and pass the real payment link " +
      "as actionUrl if one exists.",
    parameters: {
      type: "object",
      properties: {
        title: { type: "string", description: "Short task title." },
        type: { type: "string", enum: ["bill", "message", "document", "task"] },
        category: { type: "string", enum: ["personal", "work", "finance", "purchases"] },
        priority: { type: "string", enum: ["urgent", "high", "normal", "low"] },
        amount: { type: "string", description: "Amount as a plain number string, if this is a bill. Omit otherwise." },
        currency: { type: "string", description: "e.g. ILS or USD. Omit if not a bill." },
        dueDate: { type: "string", description: "ISO date (YYYY-MM-DD) if known. Omit otherwise." },
        actionUrl: { type: "string", description: "A real payment/action link from get_email_details, if one exists. Never invent one." },
        why: { type: "string", description: "One short sentence explaining why this was created, in the source message's language." },
        sourceRef: { type: "string", description: "The Gmail message id this came from, if you have it, for dedup." },
      },
      required: ["title"],
    },
  },
];

export function makeToolExecutor(userId: string) {
  return async function execute(name: string, args: Record<string, unknown>): Promise<Record<string, unknown>> {
    switch (name) {
      case "search_tasks": {
        const status = String(args.status || "open");
        const query = args.query ? String(args.query) : undefined;
        const tasks = await prisma.task.findMany({
          where: {
            userId,
            ...(status !== "any" ? { status } : {}),
            ...(query ? { title: { contains: query, mode: "insensitive" } } : {}),
          },
          orderBy: { due: "asc" },
          take: 15,
        });
        return {
          count: tasks.length,
          tasks: tasks.map((t) => ({
            title: t.title, status: t.status, priority: t.priority, due: t.due,
            amount: t.amount, currency: t.currency, source: t.source,
          })),
        };
      }

      case "search_gmail": {
        const integration = await prisma.integration.findUnique({ where: { userId_provider: { userId, provider: "google" } } });
        if (!integration || integration.status !== "connected") {
          return { error: "Gmail isn't connected for this person yet." };
        }
        const gmail = await getGmailClient(integration);
        const max = Math.min(Number(args.maxResults) || 5, 10);
        const list = await gmail.users.messages.list({ userId: "me", q: String(args.query || ""), maxResults: max });
        const ids = list.data.messages ?? [];
        const messages = await Promise.all(
          ids.map(async (m) => {
            const full = await gmail.users.messages.get({
              userId: "me", id: m.id!, format: "metadata", metadataHeaders: ["Subject", "From", "Date"],
            });
            const headers = full.data.payload?.headers ?? [];
            const get = (n: string) => headers.find((h) => h.name === n)?.value ?? "";
            return { id: m.id, subject: get("Subject"), from: get("From"), date: get("Date"), snippet: full.data.snippet ?? "" };
          })
        );
        return { count: messages.length, messages };
      }

      case "search_calendar": {
        const integration = await prisma.integration.findUnique({ where: { userId_provider: { userId, provider: "google" } } });
        if (!integration || integration.status !== "connected") {
          return { error: "Calendar isn't connected for this person yet." };
        }
        const calendar = await getCalendarClient(integration);
        const daysAhead = Number(args.daysAhead) || 7;
        const timeMin = new Date().toISOString();
        const timeMax = new Date(Date.now() + daysAhead * 86400000).toISOString();
        const res = await calendar.events.list({
          calendarId: "primary", timeMin, timeMax, singleEvents: true, orderBy: "startTime", maxResults: 20,
        });
        const events = (res.data.items ?? []).map((e) => ({
          title: e.summary, start: e.start?.dateTime || e.start?.date, end: e.end?.dateTime || e.end?.date,
        }));
        return { count: events.length, events };
      }

      case "get_recent_activity": {
        const limit = Math.min(Number(args.limit) || 10, 25);
        const activity = await prisma.activityEvent.findMany({
          where: { userId }, orderBy: { createdAt: "desc" }, take: limit,
        });
        return { count: activity.length, activity: activity.map((a) => ({ text: a.text, kind: a.kind, when: a.createdAt })) };
      }

      case "get_email_details": {
        const integration = await prisma.integration.findUnique({ where: { userId_provider: { userId, provider: "google" } } });
        if (!integration || integration.status !== "connected") {
          return { error: "Gmail isn't connected for this person yet." };
        }
        const messageId = String(args.messageId || "");
        if (!messageId) return { error: "messageId is required" };
        const gmail = await getGmailClient(integration);
        return getMessageDetails(gmail, messageId);
      }

      case "create_task": {
        const title = String(args.title || "").trim().slice(0, 200);
        if (!title) return { error: "title is required" };

        // If a real Gmail message id was provided, tag the source as gmail so the
        // dashboard's "open email" link actually works — only fall back to a
        // synthetic chat-only key when we truly don't have one.
        const providedRef = args.sourceRef ? String(args.sourceRef) : null;
        const sourceRef = providedRef || `chat:${Date.now()}:${Math.random().toString(36).slice(2, 8)}`;
        const source = providedRef ? "gmail" : "chat";

        const user = await prisma.user.findUnique({ where: { id: userId } });
        if (!user) return { error: "User not found" };

        const dueRaw = args.dueDate ? new Date(String(args.dueDate)) : null;
        const due = dueRaw && !isNaN(dueRaw.getTime()) ? dueRaw : null;

        // Only accept an actionUrl that's a real, well-formed http(s) link — cheap guard
        // against a malformed or invented value slipping through.
        const rawUrl = args.actionUrl ? String(args.actionUrl) : null;
        const actionUrl = rawUrl && /^https?:\/\//.test(rawUrl) ? rawUrl : null;

        const task = await prisma.task.upsert({
          where: { userId_sourceRef: { userId, sourceRef } },
          create: {
            userId,
            householdId: user.householdId,
            sourceRef,
            source,
            title,
            type: (args.type as string) || "task",
            category: (args.category as string) || "personal",
            priority: (args.priority as string) || "normal",
            amount: args.amount ? Number(args.amount) : null,
            currency: args.currency ? String(args.currency) : null,
            due,
            actionUrl,
            why: args.why ? String(args.why) : null,
            aiSummary: args.why ? String(args.why) : null,
          },
          update: {}, // already exists (created earlier by chat or by the background sync) — leave it alone
        });

        await prisma.activityEvent.create({
          data: { userId, text: `Added "${title}" from a chat check.`, kind: "tasks" },
        });

        return { created: true, taskId: task.id, title: task.title };
      }

      default:
        return { error: `Unknown tool: ${name}` };
    }
  };
}

export const ASSISTANT_SYSTEM_PROMPT = `You are the AiMe assistant, chatting directly with the person whose account this is.
You have tools to look up their AiMe tasks, search their Gmail, get one email's full body and links, list their upcoming
Calendar events, see recent automated activity, and add a new task. Use a tool whenever the answer depends on their actual
data rather than general knowledge — don't guess.

Always call the relevant tool fresh for the current question, even if you or the person discussed something similar earlier
in this conversation. Email and calendar contents can change between messages, so an earlier answer in this chat is never
a substitute for checking again right now.

Scope is narrowed on purpose right now: organize bills/payments and important messages only — not appointments,
invitations, birthdays, or generic reminders, even though those might normally be worth tracking. The only things that
should never become tasks are pure marketing/promotional email and routine notification digests with nothing to act on.

When asked to check email for bills, don't rely on a single vague search. Gmail search only matches literal words, so run
a few searches with concrete terms rather than one broad query — for example bill/invoice/payment/due/receipt in English,
and חשבונית, חשבון, תשלום, לתשלום, קבלה in Hebrew if the inbox may be in Hebrew. A person saying "I have bills in my
inbox" and not seeing them means the search missed them, not that they don't exist — search harder before concluding
there's nothing there.

For a bill, call get_email_details on it first to read the real body and find any payment link — only ever use a link
that tool actually returns, never invent or guess one. Then call search_tasks to make sure it isn't already tracked, then
create_task, passing the Gmail message's id as sourceRef and the real link as actionUrl if you found one. This mirrors
what AiMe's automatic background check already does on its own schedule, so doing it from chat needs no separate
permission.

You cannot send emails, create calendar events, pay bills, or change an existing task's status; if asked to do one of
those, tell them to use the relevant button in the app instead of pretending to do it yourself.

Reply in the same language the person writes to you in — if they write in Hebrew, respond in Hebrew. Separately, when you
summarize or quote something from an email or message, keep that content in whatever language it was originally written
in — don't translate a Hebrew email's subject or details into English (or vice versa) just because your own reply happens
to be in a different language. Keep replies short, warm, and direct.`;
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
assistant app called AiMe. Right now, scope is narrowed on purpose to two kinds of things: bills/payments, and
important messages that genuinely need a response or action (a document to sign, a direct question awaiting a
reply, a real deadline). Do NOT flag appointments, calendar invitations, birthdays, RSVPs, or generic reminders as
actionable right now, even if they'd normally qualify — that's out of scope for this pass. Pure marketing/promotional
email and routine notification digests (e.g. "you have 5 new messages") are never actionable.

You may be given a list of candidate links found in the message body. If this looks like a bill and one of those
links is plausibly the payment/action page (e.g. its text or URL path mentions pay, payment, invoice, bill, account,
checkout), set "actionUrl" to that exact URL, copied verbatim from the list — never invent or guess a URL that
wasn't given to you. If no candidate links were given, or none look like the right one, set "actionUrl" to null.

Respond with ONLY a JSON object, no prose, no markdown fences, matching exactly this shape:
{"isActionable": boolean, "title": string, "type": "bill"|"message"|"document"|"task",
 "category": "personal"|"work"|"finance"|"purchases",
 "priority": "urgent"|"high"|"normal"|"low", "amount": number|null, "currency": string|null,
 "dueDate": string|null, "actionUrl": string|null, "whySummary": string}

"whySummary" is one short sentence explaining, in plain language, what in the message caused you to
create this task (e.g. "Contains an amount, a due date, and a payment link."). If isActionable is
false, still return valid JSON with isActionable:false and the other fields as null/empty.

Write "title" and "whySummary" in the same language as the source message — if the message is in
Hebrew, respond in Hebrew; if it's in English, respond in English.`;

// Haiku is intentionally used here: this call runs once per candidate message on every sync,
// so cost and latency matter far more than raw capability for a one-sentence classification task.
const MODEL = "claude-haiku-4-5-20251001";

export async function extractTask(sourceLabel: string, text: string, links: string[] = []): Promise<ExtractedTask | null> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY is not set");

  const linksBlock = links.length
    ? `\n\nCandidate links found in this message:\n${links.map((l) => `- ${l}`).join("\n")}`
    : "";

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 400,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: `Source: ${sourceLabel}\n\nMessage:\n${text.slice(0, 4000)}${linksBlock}` }],
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
    // Guard against a hallucinated URL slipping through despite the instruction —
    // only keep actionUrl if it's one of the links we actually gave the model.
    if (parsed.actionUrl && !links.includes(parsed.actionUrl)) {
      parsed.actionUrl = null;
    }
    return parsed;
  } catch {
    console.error("Could not parse extraction response:", raw);
    return null;
  }
}
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/lib"
cat > "src/lib/gemini.ts" << 'AIME_HEREDOC_EOF_9f2c'
// Talks to Google's Gemini API (the classic generateContent endpoint — Google's newer
// "Interactions API" became their recommended path in mid-2026, but generateContent
// remains fully supported and is the simpler, more stable choice here).
//
// This module knows nothing about tasks, Gmail, or Calendar — it just runs the
// request/response loop and calls back into whatever tool executors it's given.
// See lib/assistant-tools.ts for what the assistant can actually look up.

export type GeminiPart =
  | { text: string }
  | { functionCall: { name: string; args: Record<string, unknown> }; thoughtSignature?: string }
  | { functionResponse: { name: string; response: Record<string, unknown> } };

export type GeminiContent = { role: "user" | "model"; parts: GeminiPart[] };

export type ToolDeclaration = {
  name: string;
  description: string;
  parameters: {
    type: "object";
    properties: Record<string, { type: string; description?: string; enum?: string[] }>;
    required?: string[];
  };
};

const MODEL = process.env.GEMINI_MODEL || "gemini-3.6-flash";

async function callGemini(contents: GeminiContent[], tools: ToolDeclaration[], systemText: string) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error("GEMINI_API_KEY is not set");

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemText }] },
        contents,
        tools: tools.length ? [{ functionDeclarations: tools }] : undefined,
        generationConfig: { temperature: 0.4 },
      }),
    }
  );

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`Gemini API error ${res.status}: ${body.slice(0, 500)}`);
  }
  return res.json();
}

/**
 * Runs the chat loop: sends the conversation + tool definitions to Gemini, and any time
 * it asks to call a tool, executes it locally and feeds the result back — up to a small
 * round cap so a confused model can't loop forever — until it returns plain text.
 */
export async function chatWithTools(
  history: GeminiContent[],
  tools: ToolDeclaration[],
  executeTool: (name: string, args: Record<string, unknown>) => Promise<Record<string, unknown>>,
  systemText: string,
  maxRounds = 20
): Promise<{ reply: string; toolCalls: { name: string; args: unknown }[] }> {
  const contents = [...history];
  const toolCalls: { name: string; args: unknown }[] = [];

  for (let round = 0; round < maxRounds; round++) {
    const data = await callGemini(contents, tools, systemText);
    const candidate = data?.candidates?.[0];
    const parts: GeminiPart[] = candidate?.content?.parts ?? [];

    const functionCallPart = parts.find((p): p is Extract<GeminiPart, { functionCall: any }> => "functionCall" in p);

    if (!functionCallPart) {
      const text = parts.map((p) => ("text" in p ? p.text : "")).join("").trim();
      return { reply: text || "I didn't get a response back — try asking again.", toolCalls };
    }

    const { name, args } = functionCallPart.functionCall;
    toolCalls.push({ name, args });

    let result: Record<string, unknown>;
    try {
      result = await executeTool(name, args || {});
    } catch (err: any) {
      result = { error: err?.message || "Tool call failed" };
    }

    contents.push({ role: "model", parts: [functionCallPart] });
    contents.push({ role: "user", parts: [{ functionResponse: { name, response: result } }] });
  }

  return { reply: "That took more steps than I could finish in one go — try narrowing the question.", toolCalls };
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

// Narrowed on purpose for now, per explicit request: bills/payments and important
// messages only — not appointments, invitations, birthdays, or generic reminders.
const CANDIDATE_QUERY =
  '(bill OR invoice OR payment OR due OR receipt OR "sign" OR deadline OR ' +
  'חשבונית OR חשבון OR תשלום OR לתשלום OR קבלה OR חתימה OR "מועד אחרון")';

function decodeBase64Url(data?: string | null): string {
  if (!data) return "";
  return Buffer.from(data.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf-8");
}

// Walks a Gmail MIME payload to find readable body text, preferring plain text
// over HTML since HTML markup just adds noise for both link-extraction and the AI.
function extractBodyText(payload: any): string {
  if (!payload) return "";
  if (payload.body?.data) return decodeBase64Url(payload.body.data);
  const parts: any[] = payload.parts || [];
  const plain = parts.find((p) => p.mimeType === "text/plain");
  if (plain?.body?.data) return decodeBase64Url(plain.body.data);
  const html = parts.find((p) => p.mimeType === "text/html");
  if (html?.body?.data) return decodeBase64Url(html.body.data);
  for (const p of parts) {
    const nested = extractBodyText(p);
    if (nested) return nested;
  }
  return "";
}

// Pulls real URLs out of the body so the AI only ever picks from links that
// genuinely exist in the email, rather than inventing one.
export function extractLinks(bodyText: string, max = 10): string[] {
  const matches = bodyText.match(/https?:\/\/[^\s"'<>\)]+/g) ?? [];
  const cleaned = matches.map((u) => u.replace(/[.,;]+$/, ""));
  return Array.from(new Set(cleaned)).slice(0, max);
}

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
        format: "full",
      });
      const headers = full.data.payload?.headers ?? [];
      const get = (name: string) => headers.find((h) => h.name === name)?.value ?? "";
      const bodyText = extractBodyText(full.data.payload);
      return {
        id: m.id!,
        subject: get("Subject"),
        from: get("From"),
        date: get("Date"),
        snippet: full.data.snippet ?? "",
        bodyText: bodyText.replace(/\r/g, "").slice(0, 4000),
        links: extractLinks(bodyText),
      };
    })
  );
  return messages;
}

function collectAttachments(
  payload: any,
  out: { attachmentId: string; filename: string; mimeType: string; size?: number }[] = []
) {
  if (!payload) return out;
  if (payload.filename && payload.body?.attachmentId) {
    out.push({
      attachmentId: payload.body.attachmentId,
      filename: payload.filename,
      mimeType: payload.mimeType || "application/octet-stream",
      size: payload.body.size,
    });
  }
  for (const p of payload.parts || []) collectAttachments(p, out);
  return out;
}

export async function listAttachments(gmail: gmail_v1.Gmail, messageId: string) {
  const full = await gmail.users.messages.get({ userId: "me", id: messageId, format: "full" });
  return collectAttachments(full.data.payload);
}

export async function getAttachmentBytes(gmail: gmail_v1.Gmail, messageId: string, attachmentId: string): Promise<Buffer> {
  const res = await gmail.users.messages.attachments.get({ userId: "me", messageId, id: attachmentId });
  return Buffer.from((res.data.data || "").replace(/-/g, "+").replace(/_/g, "/"), "base64");
}

export async function getMessageDetails(gmail: gmail_v1.Gmail, messageId: string) {
  const full = await gmail.users.messages.get({ userId: "me", id: messageId, format: "full" });
  const headers = full.data.payload?.headers ?? [];
  const get = (name: string) => headers.find((h) => h.name === name)?.value ?? "";
  const bodyText = extractBodyText(full.data.payload);
  return {
    subject: get("Subject"),
    from: get("From"),
    date: get("Date"),
    bodyText: bodyText.replace(/\r/g, "").slice(0, 4000),
    links: extractLinks(bodyText),
  };
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
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/lib"
cat > "src/lib/google.ts" << 'AIME_HEREDOC_EOF_9f2c'
import { google } from "googleapis";

// gmail.modify (not just .readonly) is required so a dismissed task can move its
// source email out of the inbox into a label — it's a superset of read access, so
// nothing else changes. calendar.events is included only so a user can click "Add
// to calendar" on a AiMe suggestion — that still requires their explicit click
// (see api/calendar/add), never a silent write.
export const GOOGLE_SCOPES = [
  "https://www.googleapis.com/auth/gmail.modify",
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
cat > "src/lib/i18n.ts" << 'AIME_HEREDOC_EOF_9f2c'
"use client";
import { useCallback, useEffect, useState } from "react";

export type Lang = "en" | "he";

// Keep this small and flat on purpose — it covers navigation and the screens people
// look at daily (Today, Connections, Account, Chat). Longer copy (onboarding prose,
// error messages) stays in English for now; extend this dictionary if that's needed.
const DICT = {
  today: { en: "Today", he: "היום" },
  chat: { en: "Chat", he: "צ'אט" },
  connections: { en: "Connections", he: "חיבורים" },
  account: { en: "Account", he: "חשבון" },
  backToToday: { en: "Back to Today", he: "חזרה להיום" },
  signOut: { en: "Sign out", he: "התנתקות" },
  checkNow: { en: "Check now", he: "בדוק עכשיו" },
  expand: { en: "Expand", he: "הרחבה" },
  send: { en: "Send", he: "שליחה" },
  thinking: { en: "Thinking…", he: "חושב…" },
  askPlaceholder: { en: "Ask AiMe anything about your inbox, calendar, or tasks…", he: "שאל את AiMe על המייל, היומן או המשימות שלך…" },
  askShort: { en: "Ask AiMe…", he: "שאל את AiMe…" },
  chatEmpty: {
    en: "Ask about your bills, what's on your calendar this week, or what AiMe has found recently — it can look those up for real. It won't send anything or change a task's status from here.",
    he: "שאל על החשבונות שלך, מה יש ביומן השבוע, או מה AiMe מצא לאחרונה — הוא באמת יבדוק את זה. הוא לא ישלח כלום ולא ישנה סטטוס של משימה מכאן.",
  },
  connectionsTitle: { en: "Connections", he: "חיבורים" },
  connectionsLead: {
    en: "Connect or reconnect anything here, any time — this isn't just a one-time onboarding step.",
    he: "אפשר לחבר או לחבר מחדש כל דבר כאן, בכל זמן — זה לא רק שלב חד-פעמי בהרשמה.",
  },
  proactivityTitle: { en: "How proactive should AiMe be?", he: "כמה יזום AiMe צריך להיות?" },
  accountTitle: { en: "Account & sharing", he: "חשבון ושיתוף" },
  language: { en: "Interface language", he: "שפת הממשק" },
  nothingHere: { en: "Nothing here yet.", he: "אין כאן כלום עדיין." },
  loading: { en: "Loading…", he: "טוען…" },
  complete: { en: "Complete", he: "בוצע" },
  completed: { en: "Completed", he: "הושלם" },
  dismiss: { en: "Dismiss", he: "התעלם" },
  openEmail: { en: "Open email", he: "פתח מייל" },
  overdue: { en: "Overdue", he: "באיחור" },
  dueToday: { en: "Due today", he: "מועד היום" },
  dueTomorrow: { en: "Due tomorrow", he: "מועד מחר" },
  sittingAWhile: { en: "Been sitting a while", he: "ממתין כבר זמן מה" },
  needsAttention: { en: "Needs attention", he: "דורש תשומת לב" },
} satisfies Record<string, Record<Lang, string>>;

export type DictKey = keyof typeof DICT;

function applyDocumentLang(lang: Lang) {
  if (typeof document === "undefined") return;
  document.documentElement.lang = lang;
  document.documentElement.dir = lang === "he" ? "rtl" : "ltr";
}

const STORAGE_KEY = "aime:lang";

export function useLang() {
  const [lang, setLangState] = useState<Lang>("en");

  useEffect(() => {
    const saved = (typeof window !== "undefined" && (localStorage.getItem(STORAGE_KEY) as Lang)) || "en";
    setLangState(saved);
    applyDocumentLang(saved);
  }, []);

  const setLang = useCallback((l: Lang) => {
    localStorage.setItem(STORAGE_KEY, l);
    setLangState(l);
    applyDocumentLang(l);
  }, []);

  const t = useCallback((key: DictKey) => DICT[key]?.[lang] ?? String(key), [lang]);

  return { lang, setLang, t };
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
  type?: "bill" | "message" | "document" | "task";
  category?: "personal" | "work" | "finance" | "purchases";
  priority?: "urgent" | "high" | "normal" | "low";
  amount?: number;
  currency?: string;
  dueDate?: string; // ISO date, if present
  actionUrl?: string | null; // a real link copied from the source message, e.g. a payment page
  whySummary?: string; // one sentence, shown to the user as "why AiMe created this"
};
AIME_HEREDOC_EOF_9f2c

mkdir -p "src/lib"
cat > "src/lib/useAssistantChat.ts" << 'AIME_HEREDOC_EOF_9f2c'
"use client";
import { useEffect, useState } from "react";

export type ChatMessage = { id: string; role: "user" | "model"; content: string };

export function useAssistantChat(shouldLoad: boolean) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState("");
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    if (!shouldLoad || loaded) return;
    fetch("/api/chat")
      .then((r) => r.json())
      .then((d) => setMessages(d.messages ?? []))
      .finally(() => setLoaded(true));
  }, [shouldLoad, loaded]);

  async function send(text: string) {
    const trimmed = text.trim();
    if (!trimmed || sending) return;
    setError("");
    setMessages((m) => [...m, { id: "temp-" + Date.now(), role: "user", content: trimmed }]);
    setSending(true);
    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ message: trimmed }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || `Status ${res.status}`);
      setMessages((m) => [...m, { id: "reply-" + Date.now(), role: "model", content: data.reply }]);
    } catch (err: any) {
      setError(err?.message || "Couldn't reach the assistant.");
    } finally {
      setSending(false);
    }
  }

  return { messages, sending, error, send };
}
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
