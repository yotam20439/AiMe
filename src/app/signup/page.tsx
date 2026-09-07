"use client";
import { useState } from "react";
import { signIn } from "next-auth/react";
import { useRouter } from "next/navigation";
import Link from "next/link";

export default function SignupPage() {
  const router = useRouter();
  const [mode, setMode] = useState<"create" | "join">("create");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [householdName, setHouseholdName] = useState("");
  const [inviteCode, setInviteCode] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    const res = await fetch("/api/signup", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ mode, name, email, password, householdName, inviteCode }),
    });
    const data = await res.json();
    if (!res.ok) {
      setLoading(false);
      setError(data.error || "Something went wrong.");
      return;
    }
    await signIn("credentials", { email, password, redirect: false });
    setLoading(false);
    router.push("/onboarding");
  }

  return (
    <div className="shell">
      <form className="panel" onSubmit={submit}>
        <h1>Create your account</h1>
        <p className="lead">One household can hold a couple of people, each with their own login.</p>
        {error && <div className="error">{error}</div>}
        <div className="seg">
          <button type="button" className={mode === "create" ? "on" : ""} onClick={() => setMode("create")}>Start a household</button>
          <button type="button" className={mode === "join" ? "on" : ""} onClick={() => setMode("join")}>Join with a code</button>
        </div>
        <div className="field">
          <label>Your name</label>
          <input className="input" required value={name} onChange={(e) => setName(e.target.value)} />
        </div>
        <div className="field">
          <label>Email</label>
          <input className="input" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        </div>
        <div className="field">
          <label>Password</label>
          <input className="input" type="password" required minLength={8} value={password} onChange={(e) => setPassword(e.target.value)} />
        </div>
        {mode === "create" ? (
          <div className="field">
            <label>Household name (e.g. "The Cohens")</label>
            <input className="input" value={householdName} onChange={(e) => setHouseholdName(e.target.value)} placeholder="Optional" />
          </div>
        ) : (
          <div className="field">
            <label>Invite code from whoever set up your household</label>
            <input className="input" required value={inviteCode} onChange={(e) => setInviteCode(e.target.value)} />
          </div>
        )}
        <button className="btn primary" disabled={loading}>{loading ? "Creating…" : "Continue"}</button>
        <p className="foot">Already have an account? <Link href="/login">Sign in</Link></p>
      </form>
    </div>
  );
}
