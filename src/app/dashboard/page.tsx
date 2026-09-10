"use client";
import { useEffect, useState } from "react";
import { useLang } from "@/lib/i18n";
import AppShell from "@/components/AppShell";

type Task = {
  id: string; title: string; type: string; source: string; priority: string; status: string;
  category: string; due: string | null; amount: number | null; currency: string | null;
  aiSummary: string | null; why: string | null; sourceRef: string | null; actionUrl: string | null;
  emailDate: string | null; createdAt: string; user: { name: string };
};

type Attachment = { attachmentId: string; filename: string; mimeType: string; size?: number };

const TYPE_ICON: Record<string, string> = { bill: "💳", appointment: "📅", document: "📄", message: "💬", task: "✅" };
const PRIORITY_RANK: Record<string, number> = { urgent: 0, high: 1, normal: 2, low: 3 };
const STALE_DAYS = 5;

function daysBetween(a: Date, b: Date) {
  return Math.round((a.getTime() - b.getTime()) / 86400000);
}

// Priority first, then soonest due date, then oldest-sent — so something urgent
// today outranks something normal next week, and among equals, whatever was
// actually sent longest ago surfaces first rather than getting buried by newer arrivals.
function smartSort(tasks: Task[]): Task[] {
  return [...tasks].sort((a, b) => {
    const pr = (PRIORITY_RANK[a.priority] ?? 9) - (PRIORITY_RANK[b.priority] ?? 9);
    if (pr !== 0) return pr;
    const ad = a.due ? new Date(a.due).getTime() : Infinity;
    const bd = b.due ? new Date(b.due).getTime() : Infinity;
    if (ad !== bd) return ad - bd;
    const aSent = new Date(a.emailDate ?? a.createdAt).getTime();
    const bSent = new Date(b.emailDate ?? b.createdAt).getTime();
    return aSent - bSent;
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
  // Staleness is measured from when the email was actually sent, not from when AiMe
  // happened to find it — an old bill that just got scraped is still old.
  const sentAt = new Date(t.emailDate ?? t.createdAt);
  if (daysBetween(now, sentAt) >= STALE_DAYS) {
    return { label: tt("sittingAWhile"), tone: "amber" };
  }
  return null;
}

function gmailLink(sourceRef: string) {
  return `https://mail.google.com/mail/u/0/#all/${sourceRef}`;
}

function attachmentUrl(messageId: string, a: Attachment) {
  const params = new URLSearchParams({
    messageId, attachmentId: a.attachmentId, filename: a.filename, mimeType: a.mimeType,
  });
  return `/api/gmail/attachment?${params.toString()}`;
}

export default function Dashboard() {
  const { t } = useLang();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [notice, setNotice] = useState<string | null>(null);
  const [syncing, setSyncing] = useState(false);
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());
  const [attachments, setAttachments] = useState<Record<string, Attachment[] | "loading">>({});

  async function load() {
    setLoading(true);
    const res = await fetch("/api/tasks");
    const data = await res.json();
    setTasks(data.tasks ?? []);
    setLoading(false);
  }

  useEffect(() => {
    load();
    // Fire-and-forget: shows existing tasks immediately, then quietly checks for new
    // ones in the background rather than making the person click "Check now" first.
    setSyncing(true);
    fetch("/api/sync/me", { method: "POST" })
      .then((r) => r.json())
      .then((d) => {
        if (d?.tasksCreated > 0) {
          setNotice(`Found ${d.tasksCreated} new item${d.tasksCreated === 1 ? "" : "s"} in your inbox.`);
          load();
        }
      })
      .catch(() => {})
      .finally(() => setSyncing(false));
  }, []);

  async function toggleExpand(tk: Task) {
    const willOpen = !expandedIds.has(tk.id);
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (willOpen) next.add(tk.id); else next.delete(tk.id);
      return next;
    });
    if (willOpen && tk.source === "gmail" && !attachments[tk.id]) {
      setAttachments((a) => ({ ...a, [tk.id]: "loading" }));
      const res = await fetch(`/api/tasks/${tk.id}/attachments`);
      const data = await res.json().catch(() => ({ attachments: [] }));
      setAttachments((a) => ({ ...a, [tk.id]: data.attachments ?? [] }));
    }
  }

  async function complete(id: string) {
    const res = await fetch("/api/tasks", {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id, status: "completed" }),
    });
    const data = await res.json().catch(() => ({}));
    if (data?.inboxMoveError) setNotice(data.inboxMoveError);
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
    <AppShell>
      <div className="content" style={{ maxWidth: 1080 }}>
        <h1 style={{ fontSize: 26, letterSpacing: "-.02em" }}>{t("today")}</h1>
        {notice && <div className="error">{notice}</div>}
        {syncing && <p style={{ color: "var(--text-3)", fontSize: 12.5, margin: "0 0 12px" }}>Checking your inbox…</p>}

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
              const isOpen = expandedIds.has(tk.id);
              const atts = attachments[tk.id];
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
                    {tk.actionUrl && (
                      <a className="btn primary" style={{ width: "auto" }} href={tk.actionUrl} target="_blank" rel="noreferrer">
                        {tk.type === "bill" ? "Pay now" : t("openEmail")}
                      </a>
                    )}
                    {tk.source === "gmail" && tk.sourceRef && (
                      <a className="btn" style={{ width: "auto" }} href={gmailLink(tk.sourceRef)} target="_blank" rel="noreferrer">
                        {t("openEmail")}
                      </a>
                    )}
                    <button className="btn" style={{ width: "auto" }} onClick={() => complete(tk.id)}>{t("complete")}</button>
                    <button className="btn" style={{ width: "auto" }} onClick={() => dismiss(tk.id)}>{t("dismiss")}</button>
                    <button className="tcard-toggle" onClick={() => toggleExpand(tk)}>
                      {isOpen ? `▲ ${t("less")}` : `▼ ${t("details")}`}
                    </button>
                  </div>

                  {isOpen && (
                    <div className="tcard-details">
                      <dl>
                        <dt>Category</dt><dd>{tk.category}</dd>
                        <dt>Priority</dt><dd>{tk.priority}</dd>
                        {tk.due && <><dt>Due</dt><dd>{new Date(tk.due).toLocaleDateString()}</dd></>}
                        {tk.emailDate && <><dt>Sent</dt><dd>{new Date(tk.emailDate).toLocaleString()}</dd></>}
                        <dt>Detected</dt><dd>{new Date(tk.createdAt).toLocaleString()}</dd>
                        <dt>Source</dt><dd>{tk.source}</dd>
                        {tk.why && <><dt>Why</dt><dd>{tk.why}</dd></>}
                      </dl>
                      {tk.source === "gmail" && tk.sourceRef && (
                        <div>
                          {atts === "loading" && <p style={{ fontSize: 12.5, color: "var(--text-2)", margin: 0 }}>Checking for attachments…</p>}
                          {Array.isArray(atts) && atts.length === 0 && (
                            <p style={{ fontSize: 12.5, color: "var(--text-2)", margin: 0 }}>No attachments on this email.</p>
                          )}
                          {Array.isArray(atts) && atts.length > 0 && (
                            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
                              {atts.map((a) => (
                                <a key={a.attachmentId} className="attach-item" href={attachmentUrl(tk.sourceRef as string, a)} target="_blank" rel="noreferrer">
                                  📎 <span>{a.filename}</span>
                                </a>
                              ))}
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  )}
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
    </AppShell>
  );
}
