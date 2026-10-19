import { categories } from "./catalog.ts";

export type ReportRecord = {
  key: string;
  market_date: string;
  category_key: string | null;
  segment_key?: string | null;
  kind: string;
  title: string;
  byte_count: number;
};

export type ReportView = ReportRecord & {
  label: string;
  kindLabel: string;
  href: string;
  sizeLabel: string;
  segmentLabel: string;
};

export type ReportArchiveState = "loading" | "empty" | "ready" | "error";
export type ReportKindFilter = "all" | "daily" | "weekly";

export function readReportPayload(value: unknown): ReportRecord[] {
  const rows = value && typeof value === "object" && "reports" in value ? value.reports : null;
  if (!Array.isArray(rows) || rows.some(row => !row || typeof row !== "object" ||
    !["key", "market_date", "kind", "title"].every(key => typeof row[key] === "string") ||
    typeof row.byte_count !== "number" || !Number.isFinite(row.byte_count) || row.byte_count < 0 ||
    (row.category_key !== null && typeof row.category_key !== "string"))) throw new Error("报告数据格式异常");
  return rows as ReportRecord[];
}

export function parseReportKindFilter(value: string | null | undefined): ReportKindFilter {
  return value === "daily" || value === "weekly" ? value : "all";
}

export function filterReportRecords(records: ReportRecord[], kind: ReportKindFilter, archiveDate = ""): ReportRecord[] {
  return kind === "all" && !archiveDate ? records : records.filter((record) => (kind === "all" || record.kind === kind) && (!archiveDate || record.market_date === archiveDate));
}

export function resolveReportArchiveState(loaded: boolean, reportCount: number, failed = false): ReportArchiveState {
  if (!loaded) return "loading";
  if (failed) return "error";
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
      segmentLabel: record.segment_key ? (record.segment_key === "all" ? "全部榜单" : record.segment_key) : "原始榜单历史报告",
    }];
  });
}
