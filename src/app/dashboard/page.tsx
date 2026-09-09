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

export default function Dashboard() {
  const { data: session } = useSession();
  const { t } = useLang();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [notice, setNotice] = useState<string | null>(null);

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
                    {tk.actionUrl ? (
                      <a className="btn primary" style={{ width: "auto" }} href={tk.actionUrl} target="_blank" rel="noreferrer">
                        {tk.type === "bill" ? "Pay now" : t("openEmail")}
                      </a>
                    ) : tk.source === "gmail" && tk.sourceRef ? (
                      <a className="btn" style={{ width: "auto" }} href={gmailLink(tk.sourceRef)} target="_blank" rel="noreferrer">
                        {t("openEmail")}
                      </a>
                    ) : null}
                    <button className="btn" style={{ width: "auto" }} onClick={() => complete(tk.id)}>{t("complete")}</button>
                    <button className="btn" style={{ width: "auto" }} onClick={() => dismiss(tk.id)}>{t("dismiss")}</button>
                  </div>
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
