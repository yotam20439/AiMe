export type ExtractedTask = {
  isActionable: boolean;
  title?: string;
  type?: "bill" | "message" | "document" | "task";
  category?: "personal" | "work" | "finance" | "purchases";
  priority?: "urgent" | "high" | "normal" | "low";
  amount?: number;
  currency?: string;
  dueDate?: string; // ISO date, if present
  actionUrl?: string | null; // a real link copied from the source message, e.g. a payment page
  whySummary?: string; // one sentence, shown to the user as "why AiMe created this"
};
