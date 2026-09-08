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
