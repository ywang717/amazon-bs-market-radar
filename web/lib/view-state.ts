export function patchViewQuery(search: string, changes: Record<string, string | number | null>): string {
  const params = new URLSearchParams(search);
  for (const [key, value] of Object.entries(changes)) {
    if (value === null || value === "") params.delete(key);
    else params.set(key, String(value));
  }
  return params.toString();
}

export function readChoice<T extends string>(params: URLSearchParams, key: string, choices: readonly T[], fallback: T): T {
  const value = params.get(key);
  return choices.includes(value as T) ? value as T : fallback;
}

export function pageRows<T>(rows: readonly T[], value: string | null, size: number) {
  const n = value && /^[1-9]\d*$/.test(value) ? Number(value) : 1;
  const pages = Math.max(1, Math.ceil(rows.length / size));
  const page = Math.min(Number.isSafeInteger(n) ? n : 1, pages);
  return { rows: rows.slice((page - 1) * size, page * size), page, pages, total: rows.length };
}

export function safeListReturn(value: unknown, fallback: string): string {
  if (typeof value !== "string" || !value.startsWith("/") || value.startsWith("//")) return fallback;
  try {
    const url = new URL(value, "https://market-radar.local");
    return url.origin === "https://market-radar.local" && ["/products", "/rankings", "/market", "/reports"].includes(url.pathname) ? `${url.pathname}${url.search}` : fallback;
  } catch { return fallback; }
}
