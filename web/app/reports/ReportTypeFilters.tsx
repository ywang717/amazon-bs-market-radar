"use client";
import { serializeMarketContext, type MarketContext } from "@/lib/market-context";
import type { ReportKindFilter } from "@/lib/reports-view";
import { useViewQuery } from "../components/useViewQuery";

export function ReportTypeFilters({ context, marketDate, kind }: { context: MarketContext; marketDate: string; kind: ReportKindFilter }) {
  const { params } = useViewQuery();
  return <nav className="archiveFilters" aria-label="报告类型筛选">{(["all", "daily", "weekly"] as const).map(filter => {
    const query = new URLSearchParams(serializeMarketContext(context, params));
    query.set("date", params.get("date") || marketDate);
    query.set("kind", filter);
    query.delete("archivePage");
    return <a key={filter} target="_top" className={`selectButton${kind === filter ? " active" : ""}`} aria-current={kind === filter ? "page" : undefined} href={`?${query}`}>{filter === "all" ? "全部报告⌄" : filter === "daily" ? "日报" : "周报"}</a>;
  })}</nav>;
}
