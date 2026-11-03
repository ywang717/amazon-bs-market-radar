"use client";

import { useEffect } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { MARKET_CONFIG, resolveMarketDate, resolvePageMarketContext, resolveSegmentForCategory, serializeMarketContext, type MarketContext as MarketContextValue, type PageMarket } from "@/lib/market-context";
import { MarketDateCalendar } from "./MarketDateCalendar";

export function MarketContext({ marketDate, validMarketDates = [marketDate], context, page }: { marketDate: string; validMarketDates?: string[]; context: MarketContextValue; page: PageMarket }) {
  const pathname = usePathname();
  const router = useRouter();
  const searchParams = useSearchParams();
  const currentQuery = searchParams.toString();
  const resolved = resolvePageMarketContext(page, new URLSearchParams(currentQuery));
  const resolvedDate = resolveMarketDate(searchParams.get("date"), validMarketDates);
  const normalizedParams = new URLSearchParams(resolved.searchParams);
  if (searchParams.has("date") && resolvedDate.marketDate) normalizedParams.set("date", resolvedDate.marketDate);
  const normalizedQuery = normalizedParams.toString();

  useEffect(() => {
    if (resolved.needsNormalization || resolvedDate.needsNormalization) router.replace(`${pathname}?${normalizedQuery}`, { scroll: false });
  }, [normalizedQuery, pathname, resolved.needsNormalization, resolvedDate.needsNormalization, router]);

  function navigate(next: MarketContextValue) {
    const params = new URLSearchParams(currentQuery);
    const query = serializeMarketContext(next, params);
    router.push(`${pathname}?${query}`, { scroll: false });
    window.dispatchEvent(new CustomEvent("market-radar:navigation", { detail: { search: query } }));
  }

  const analysisMode = searchParams.get("analysis_mode") ?? "single";
  function setMode(mode: string) {
    const params = new URLSearchParams(currentQuery);
    if (mode === "single") params.delete("analysis_mode"); else params.set("analysis_mode", mode);
    if (mode === "range") { params.set("range_end", marketDate); if (!params.get("range_start")) params.set("range_start", validMarketDates.at(-2) ?? marketDate); }
    if (mode === "compare" && !params.get("compare_date")) params.set("compare_date", validMarketDates.filter((date) => date < marketDate).at(-1) ?? marketDate);
    router.push(`${pathname}?${params.toString()}`, { scroll: false });
  }
  return <><div className="marketContextBar">
    <div className="marketContextControls" aria-label="当前页面市场">
      <span className="marketplaceLabel"><span aria-hidden="true">🇺🇸</span> 美国站</span><i aria-hidden="true">/</i>
      <label>市场<span className="srOnly">分类</span><select aria-label="市场分类" value={context.category} onChange={(event) => {
        const category = event.target.value as MarketContextValue["category"];
        navigate({ ...context, category, segment: resolveSegmentForCategory(page, category, context.segment) });
      }}>{Object.values(MARKET_CONFIG).map((market) => <option value={market.categoryId} key={market.categoryId}>{market.label}</option>)}</select></label><i aria-hidden="true">/</i>
      <label>分群<select aria-label="市场分群" value={context.segment} onChange={(event) => navigate({ ...context, segment: event.target.value as MarketContextValue["segment"] })}>{MARKET_CONFIG[context.category].segments.map((segment) => <option value={segment.key} key={segment.key}>{segment.label}</option>)}</select></label>
    </div>
    <div className="dateControl"><MarketDateCalendar marketDate={marketDate} validMarketDates={validMarketDates} /></div>
    <div className="analysisModeBar" aria-label="分析模式"><span>分析</span>{[["single", "单日"], ["compare", "两日比较"], ["range", "区间分析"]].map(([mode, label]) => <button type="button" key={mode} className={analysisMode === mode ? "active" : ""} aria-pressed={analysisMode === mode} onClick={() => setMode(mode)}>{label}</button>)}</div>
  </div>{resolvedDate.needsNormalization ? <p className="sourceNotice" role="status">所选日期 {searchParams.get("date")} 不是有效市场日，已回落到最近有效市场日。</p> : null}</>;
}
