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
