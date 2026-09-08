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
