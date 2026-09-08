"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";

type Message = { id: string; role: "user" | "model"; content: string };

export default function ChatPage() {
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

  async function send(e: React.FormEvent) {
    e.preventDefault();
    const text = input.trim();
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

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100vh" }}>
      <div className="topbar">
        <span className="brand"><img src="/logo-mark.png" alt="" /><b>AiMe</b></span>
        <div style={{ flex: 1 }} />
        <Link className="btn" style={{ width: "auto" }} href="/connections">Connections</Link>
        <Link className="btn" style={{ width: "auto" }} href="/dashboard">Today</Link>
      </div>

      <div style={{ flex: 1, overflowY: "auto", padding: "20px 16px" }}>
        <div style={{ maxWidth: 640, margin: "0 auto" }}>
          {messages.length === 0 && (
            <p style={{ color: "var(--text-2)", fontSize: 13.5 }}>
              Ask about your bills, what's on your calendar this week, or what AiMe has found recently — it can look
              those up for real. It won't send anything or change a task's status from here.
            </p>
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
          {sending && <p style={{ color: "var(--text-2)", fontSize: 13 }}>Thinking…</p>}
          {error && <div className="error">{error}</div>}
          <div ref={bottomRef} />
        </div>
      </div>

      <form onSubmit={send} style={{ borderTop: "1px solid var(--border)", padding: 14, display: "flex", gap: 8, maxWidth: 640, margin: "0 auto", width: "100%" }}>
        <input
          className="input"
          style={{ flex: 1 }}
          placeholder="Ask AiMe anything about your inbox, calendar, or tasks…"
          value={input}
          onChange={(e) => setInput(e.target.value)}
        />
        <button className="btn primary" style={{ width: "auto" }} disabled={sending}>Send</button>
      </form>
    </div>
  );
}
