"use client";
import { useEffect, useState } from "react";
import { useSession, signOut } from "next-auth/react";
import Link from "next/link";
import { useLang } from "@/lib/i18n";

type Task = {
  id: string; title: string; type: string; source: string; priority: string; status: string;
  due: string | null; amount: number | null; currency: string | null; aiSummary: string | null;
  user: { name: string };
};

export default function Dashboard() {
  const { data: session } = useSession();
  const { t } = useLang();
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
        <Link className="btn" style={{ width: "auto" }} href="/chat">{t("chat")}</Link>
        <Link className="btn" style={{ width: "auto" }} href="/connections">{t("connections")}</Link>
        <Link className="btn" style={{ width: "auto" }} href="/household">{t("account")}</Link>
        <button className="btn" style={{ width: "auto" }} onClick={() => signOut({ callbackUrl: "/login" })}>{t("signOut")}</button>
      </div>
      <div className="content">
        <h1 style={{ fontSize: 26, letterSpacing: "-.02em" }}>{t("today")}</h1>
        {loading ? (
          <p style={{ color: "var(--text-2)" }}>{t("loading")}</p>
        ) : open.length === 0 ? (
          <p style={{ color: "var(--text-2)" }}>
            Nothing here yet. Connected accounts sync automatically every 15 minutes — or trigger the cron
            endpoint manually while testing.
          </p>
        ) : (
          open.map((t2) => (
            <div className="row" key={t2.id}>
              <div className="t">
                <b>{t2.title}{t2.amount ? ` · ${t2.currency ?? ""}${t2.amount}` : ""}</b>
                <small>{t2.aiSummary ?? `${t2.source} · ${t2.priority}`}{t2.due ? ` · Due ${new Date(t2.due).toLocaleDateString()}` : ""}</small>
              </div>
              <button className="btn" style={{ width: "auto" }} onClick={() => complete(t2.id)}>{t("complete")}</button>
            </div>
          ))
        )}

        {done.length > 0 && (
          <>
            <h2 style={{ fontSize: 15, marginTop: 28, color: "var(--text-2)" }}>{t("completed")}</h2>
            {done.map((t2) => (
              <div className="row" key={t2.id} style={{ opacity: 0.6 }}>
                <div className="t"><b style={{ textDecoration: "line-through" }}>{t2.title}</b></div>
              </div>
            ))}
          </>
        )}
      </div>
    </div>
  );
}
