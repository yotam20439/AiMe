export type ExtractedTask = {
  isActionable: boolean;
  title?: string;
  type?: "bill" | "message" | "document" | "appointment" | "task";
  category?: "personal" | "work" | "finance" | "appointments" | "purchases";
  priority?: "urgent" | "high" | "normal" | "low";
  amount?: number;
  currency?: string;
  dueDate?: string; // ISO date, if present
  whySummary?: string; // one sentence, shown to the user as "why AiMe created this"
};
