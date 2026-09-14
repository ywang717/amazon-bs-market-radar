import d05 from "../data/history/2026-08-05.json" with { type: "json" };
import d06 from "../data/history/2026-08-06.json" with { type: "json" };
import d07 from "../data/history/2026-08-07.json" with { type: "json" };
import d08 from "../data/history/2026-08-08.json" with { type: "json" };
import d09 from "../data/history/2026-08-09.json" with { type: "json" };
import d10 from "../data/history/2026-08-10.json" with { type: "json" };
import d11 from "../data/history/2026-08-11.json" with { type: "json" };
import d12 from "../data/history/2026-08-12.json" with { type: "json" };
import type { Observation } from "./analytics.ts";
import type { CategoryKey } from "./catalog.ts";

export type SeedSnapshot = { market_date: string; observed_at: string; sources: Record<CategoryKey, string> } & Record<CategoryKey, Observation[]>;
export const verifiedHistory = [d05,d06,d07,d08,d09,d10,d11,d12] as unknown as SeedSnapshot[];
export const verifiedSeed = verifiedHistory.at(-1)!;
export const seedReceiptSha256 = "2af21051db294eeac0995b34e59ccadedc7c0ff4702b9a9b5c9fc0ec7fc66112";
export const qualityHistory = [
  { date: "2026-08-04", status: "partial", label: "不完整" },
  ...verifiedHistory.map(({ market_date }) => ({ date: market_date, status: "complete" as const, label: "完整" })),
] as const;
