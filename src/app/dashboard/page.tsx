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
        <span className="brand"><img src="/logo-mark.png" alt="" /><b>AiMe</b></span>
        <span style={{ color: "var(--text-2)", fontSize: 13 }}>{session?.user?.name}</span>
        <div style={{ flex: 1 }} />
        <Link className="btn" style={{ width: "auto" }} href="/chat">Chat</Link>
        <Link className="btn" style={{ width: "auto" }} href="/connections">Connections</Link>
        <Link className="btn" style={{ width: "auto" }} href="/household">Account</Link>
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
