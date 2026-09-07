"use client";
import { useState } from "react";
import { signIn } from "next-auth/react";
import { useRouter } from "next/navigation";
import Link from "next/link";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    const res = await signIn("credentials", { email, password, redirect: false });
    setLoading(false);
    if (res?.error) setError("That email and password don't match.");
    else router.push("/dashboard");
  }

  return (
    <div className="shell">
      <form className="panel" onSubmit={submit}>
        <h1>Welcome back</h1>
        <p className="lead">Sign in to your AiMe account.</p>
        {error && <div className="error">{error}</div>}
        <div className="field">
          <label>Email</label>
          <input className="input" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        </div>
        <div className="field">
          <label>Password</label>
          <input className="input" type="password" required value={password} onChange={(e) => setPassword(e.target.value)} />
        </div>
        <button className="btn primary" disabled={loading}>{loading ? "Signing in…" : "Sign in"}</button>
        <p className="foot">No account yet? <Link href="/signup">Create one</Link></p>
      </form>
    </div>
  );
}
