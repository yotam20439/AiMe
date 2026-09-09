"use client";
import { useEffect, useState } from "react";
import { useSession, signOut } from "next-auth/react";
import { usePathname, useRouter } from "next/navigation";
import { useLang } from "@/lib/i18n";
import { TodayIcon, ChatIcon, PlugIcon, UserIcon, LogOutIcon, ChevronDoubleIcon } from "@/lib/icons";

const STORAGE_KEY = "aime:sidebarCollapsed";

export default function AppShell({ children }: { children: React.ReactNode }) {
  const { data: session } = useSession();
  const { t, lang } = useLang();
  const pathname = usePathname();
  const router = useRouter();
  const [collapsed, setCollapsed] = useState(false);

  useEffect(() => {
    setCollapsed(localStorage.getItem(STORAGE_KEY) === "1");
  }, []);

  function toggle() {
    const next = !collapsed;
    setCollapsed(next);
    localStorage.setItem(STORAGE_KEY, next ? "1" : "0");
  }

  const items: { href: string; label: string; icon: React.ReactNode }[] = [
    { href: "/dashboard", label: t("today"), icon: <TodayIcon /> },
    { href: "/chat", label: t("chat"), icon: <ChatIcon /> },
    { href: "/connections", label: t("connections"), icon: <PlugIcon /> },
    { href: "/household", label: t("account"), icon: <UserIcon /> },
  ];

  return (
    <div className="app-shell">
      <aside className={`app-sidebar${collapsed ? " collapsed" : ""}`}>
        <div className="app-sidebar-top">
          <button className="app-brand" onClick={() => router.push("/dashboard")} aria-label="AiMe">
            <img src="/logo-mark.png" alt="" />
            {!collapsed && <b>AiMe</b>}
          </button>
          <button className="app-collapse-btn" onClick={toggle} aria-label={collapsed ? "Expand menu" : "Collapse menu"}>
            <ChevronDoubleIcon flipped={lang === "he" ? !collapsed : collapsed} />
          </button>
        </div>

        <nav className="app-nav">
          {items.map((it) => (
            <button
              key={it.href}
              className={`app-nav-item${pathname === it.href ? " on" : ""}`}
              onClick={() => router.push(it.href)}
              title={collapsed ? it.label : undefined}
            >
              <span className="app-nav-ic">{it.icon}</span>
              {!collapsed && <span className="lbl">{it.label}</span>}
            </button>
          ))}
        </nav>

        <div className="app-sidebar-bottom">
          {!collapsed && <div className="app-user-name">{session?.user?.name}</div>}
          <button className="app-nav-item" onClick={() => signOut({ callbackUrl: "/login" })} title={collapsed ? t("signOut") : undefined}>
            <span className="app-nav-ic"><LogOutIcon /></span>
            {!collapsed && <span className="lbl">{t("signOut")}</span>}
          </button>
        </div>
      </aside>

      <main className="app-main">{children}</main>
    </div>
  );
}
