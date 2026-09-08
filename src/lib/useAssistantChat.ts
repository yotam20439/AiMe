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
