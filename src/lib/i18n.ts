"use client";
import { useCallback, useEffect, useState } from "react";

export type Lang = "en" | "he";

// Keep this small and flat on purpose — it covers navigation and the screens people
// look at daily (Today, Connections, Account, Chat). Longer copy (onboarding prose,
// error messages) stays in English for now; extend this dictionary if that's needed.
const DICT = {
  today: { en: "Today", he: "היום" },
  chat: { en: "Chat", he: "צ'אט" },
  connections: { en: "Connections", he: "חיבורים" },
  account: { en: "Account", he: "חשבון" },
  backToToday: { en: "Back to Today", he: "חזרה להיום" },
  signOut: { en: "Sign out", he: "התנתקות" },
  checkNow: { en: "Check now", he: "בדוק עכשיו" },
  expand: { en: "Expand", he: "הרחבה" },
  send: { en: "Send", he: "שליחה" },
  thinking: { en: "Thinking…", he: "חושב…" },
  askPlaceholder: { en: "Ask AiMe anything about your inbox, calendar, or tasks…", he: "שאל את AiMe על המייל, היומן או המשימות שלך…" },
  askShort: { en: "Ask AiMe…", he: "שאל את AiMe…" },
  chatEmpty: {
    en: "Ask about your bills, what's on your calendar this week, or what AiMe has found recently — it can look those up for real. It won't send anything or change a task's status from here.",
    he: "שאל על החשבונות שלך, מה יש ביומן השבוע, או מה AiMe מצא לאחרונה — הוא באמת יבדוק את זה. הוא לא ישלח כלום ולא ישנה סטטוס של משימה מכאן.",
  },
  connectionsTitle: { en: "Connections", he: "חיבורים" },
  connectionsLead: {
    en: "Connect or reconnect anything here, any time — this isn't just a one-time onboarding step.",
    he: "אפשר לחבר או לחבר מחדש כל דבר כאן, בכל זמן — זה לא רק שלב חד-פעמי בהרשמה.",
  },
  proactivityTitle: { en: "How proactive should AiMe be?", he: "כמה יזום AiMe צריך להיות?" },
  accountTitle: { en: "Account & sharing", he: "חשבון ושיתוף" },
  language: { en: "Interface language", he: "שפת הממשק" },
  nothingHere: { en: "Nothing here yet.", he: "אין כאן כלום עדיין." },
  loading: { en: "Loading…", he: "טוען…" },
  complete: { en: "Complete", he: "בוצע" },
  completed: { en: "Completed", he: "הושלם" },
} satisfies Record<string, Record<Lang, string>>;

export type DictKey = keyof typeof DICT;

function applyDocumentLang(lang: Lang) {
  if (typeof document === "undefined") return;
  document.documentElement.lang = lang;
  document.documentElement.dir = lang === "he" ? "rtl" : "ltr";
}

const STORAGE_KEY = "aime:lang";

export function useLang() {
  const [lang, setLangState] = useState<Lang>("en");

  useEffect(() => {
    const saved = (typeof window !== "undefined" && (localStorage.getItem(STORAGE_KEY) as Lang)) || "en";
    setLangState(saved);
    applyDocumentLang(saved);
  }, []);

  const setLang = useCallback((l: Lang) => {
    localStorage.setItem(STORAGE_KEY, l);
    setLangState(l);
    applyDocumentLang(l);
  }, []);

  const t = useCallback((key: DictKey) => DICT[key]?.[lang] ?? String(key), [lang]);

  return { lang, setLang, t };
}
