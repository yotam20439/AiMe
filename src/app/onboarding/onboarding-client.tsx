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
