export interface ExampleJob {
  id: string;
  text: string;
}

export type ExampleJobState =
  | { status: "queued" | "running" }
  | { status: "complete"; result: string }
  | { status: "failed"; error: string };

export function decodeJob(value: unknown): ExampleJob | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Record<string, unknown>;
  if (typeof candidate.id !== "string" || !/^[0-9a-f-]{36}$/.test(candidate.id)) return null;
  if (typeof candidate.text !== "string" || candidate.text.length > 120 || !candidate.text.trim()) return null;
  return { id: candidate.id, text: candidate.text.trim() };
}
