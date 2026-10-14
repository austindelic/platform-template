export function parseItemTitle(value: FormDataEntryValue | null): string | null {
  if (typeof value !== "string") return null;
  const title = value.trim();
  return title.length >= 1 && title.length <= 120 ? title : null;
}
