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
