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
        <h1 style={{ fontSize: 26, letterSpacing: "-.02em" }}>Household</h1>
        {household && (
          <>
            <p style={{ color: "var(--text-2)" }}>
              Share this code with a partner or family member. When they sign up and choose
              "Join with a code," they'll land in the same household with their own login and
              their own connected accounts.
            </p>
            <div className="code-box" style={{ marginBottom: 20 }}>{household.inviteCode}</div>
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
