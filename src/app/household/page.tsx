"use client";
import { useEffect, useState } from "react";
import Link from "next/link";

type Household = { name: string; inviteCode: string; members: { id: string; name: string; email: string; role: string }[] };

export default function HouseholdPage() {
  const [household, setHousehold] = useState<Household | null>(null);

  useEffect(() => {
    fetch("/api/household").then((r) => r.json()).then((d) => setHousehold(d.household));
  }, []);

  return (
    <div>
      <div className="topbar">
        <b>AiMe</b>
        <div style={{ flex: 1 }} />
        <Link className="btn" style={{ width: "auto" }} href="/dashboard">Back to Today</Link>
      </div>
      <div className="content">
        <h1 style={{ fontSize: 26, letterSpacing: "-.02em" }}>Account &amp; sharing</h1>
        {household && (
          <>
            <p style={{ color: "var(--text-2)" }}>
              {household.members.length > 1
                ? "Everyone below shares this account, each with their own login and their own connected services."
                : "It's just you here — nothing else to set up. If you ever want to share this with a partner or family member, send them this code:"}
            </p>
            <div className="code-box" style={{ marginBottom: 8 }}>{household.inviteCode}</div>
            <p style={{ color: "var(--text-3)", fontSize: 12.5, marginTop: 0, marginBottom: 20 }}>
              They'll sign up and choose "Join someone else's," using this code.
            </p>
            {household.members.map((m) => (
              <div className="row" key={m.id}>
                <div className="t"><b>{m.name}</b><small>{m.email} · {m.role}</small></div>
              </div>
            ))}
          </>
        )}
      </div>
    </div>
  );
}
