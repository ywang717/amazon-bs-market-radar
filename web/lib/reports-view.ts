import { categories } from "./catalog.ts";

export type ReportRecord = {
  key: string;
  market_date: string;
  category_key: string | null;
  kind: string;
  title: string;
  byte_count: number;
};

export type ReportView = ReportRecord & {
  label: string;
  kindLabel: string;
  href: string;
  sizeLabel: string;
};

export type ReportArchiveState = "loading" | "empty" | "ready";

export function resolveReportArchiveState(loaded: boolean, reportCount: number): ReportArchiveState {
  if (!loaded) return "loading";
  return reportCount > 0 ? "ready" : "empty";
}

const safeKey = /^[a-z0-9][a-z0-9/_-]*\.pdf$/i;

export function buildReportView(records: ReportRecord[]): ReportView[] {
  return records.flatMap((record) => {
    const category = categories.find(({ key }) => key === record.category_key);
    if (!category || !safeKey.test(record.key) || record.key.includes("..") || !["daily", "weekly"].includes(record.kind)) return [];
    return [{
      ...record,
      label: category.label,
      kindLabel: record.kind === "daily" ? "日报" : "周报",
      href: `/api/public/reports/${record.key}`,
      sizeLabel: `${(record.byte_count / 1024).toFixed(1)} KB`,
    }];
  });
}
