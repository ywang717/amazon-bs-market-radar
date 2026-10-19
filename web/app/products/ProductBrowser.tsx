"use client";

import { useMemo } from "react";
import { formatCompactNumber, formatDeal, formatPrice, HIGH_PRESENCE_THRESHOLD, type ProductIntelligenceRow } from "@/lib/ui-intelligence";
import { ProductIdentity } from "../components/ProductIdentity";
import { RankDelta, RankDisplay } from "../components/RankDisplay";
import { productTypeFiltersForContext, serializeMarketContext, type MarketContext, type SegmentKey } from "@/lib/market-context";

import { useViewQuery } from "../components/useViewQuery";
import { readChoice } from "@/lib/view-state";

const filters = ["全部", "上升", "下降", "Top10", "新入榜", "高在榜率"] as const;
type Filter = (typeof filters)[number];

export function ProductBrowser({ rows, context, marketDate, emptyReason }: { rows: ProductIntelligenceRow[]; context: MarketContext; marketDate: string; emptyReason?: string }) {
  const { params, update } = useViewQuery();
  const query = params.get("q") ?? "";
  const filter = readChoice<Filter>(params, "filter", filters, "全部");
  const typeFilter = readChoice<SegmentKey | "all">(params, "productType", ["all", ...productTypeFiltersForContext(context).map(t => t.key)], "all");
  const returnQuery = new URLSearchParams(params); returnQuery.delete("returnTo");
  const returnTo = `/products?${returnQuery}`;
  const typeFilters = useMemo(() => productTypeFiltersForContext(context), [context]);
  const visible = useMemo(() => rows.filter((row) => {
    const matchesQuery = `${row.title} ${row.asin} ${row.brand ?? ""}`.toLowerCase().includes(query.trim().toLowerCase());
    const matchesFilter = filter === "全部"
      || (filter === "上升" && (row.delta ?? 0) > 0)
      || (filter === "Top10" && row.rank <= 10)
      || (filter === "新入榜" && row.isNew)
      || (filter === "下降" && (row.delta ?? 0) < 0)
      || (filter === "高在榜率" && (row.presencePercent ?? 0) >= HIGH_PRESENCE_THRESHOLD);
    const allowedTypes = typeFilter === "all" ? null : typeFilters.find(({ key }) => key === typeFilter)?.productTypes;
    return matchesQuery && matchesFilter && (!allowedTypes || allowedTypes.includes(row.productType));
  }), [rows, query, filter, typeFilter, typeFilters]);

  return <>
    <div className="productBrowserControls">
      <label className="productSearch"><span className="srOnly">搜索产品</span><span aria-hidden="true">⌕</span><input value={query} onChange={(event) => update({ q: event.target.value }, true)} placeholder="搜索 ASIN / 产品 / 品牌" /></label>
      <div className="filterChips" role="group" aria-label="产品筛选">{filters.map((item) => <button type="button" aria-pressed={filter === item} onClick={() => update({ filter: item === "全部" ? null : item })} key={item}>{item}</button>)}</div>
      {typeFilters.length ? <div className="filterChips" role="group" aria-label="产品类型筛选"><button type="button" aria-pressed={typeFilter === "all"} onClick={() => update({ productType: null })}>全部类型</button>{typeFilters.map((item) => <button type="button" aria-pressed={typeFilter === item.key} onClick={() => update({ productType: item.key })} key={item.key}>{item.label}</button>)}</div> : null}
      <button type="button" onClick={() => update({ q: null, filter: null, productType: null })}>清除产品筛选</button>
    </div>
    {visible.length ? <div className="rankingSurface tableScroll"><table className="productBrowserTable"><thead><tr><th>产品</th><th>品牌</th><th>当前排名</th><th>1D</th><th title="有效市场日不足，暂无法计算 7D 趋势。">7D</th><th>价格</th><th>优惠</th><th>评论数</th><th>在榜率</th></tr></thead><tbody>{visible.map((row) => <tr key={row.asin}>
      <td><ProductIdentity asin={row.asin} title={row.title} type={row.productType} href={`/products/${row.asin}?${serializeMarketContext(context, { date: marketDate })}&returnTo=${encodeURIComponent(returnTo)}`} /></td>
      <td>{row.brand ?? "未知品牌"}</td>
      <td><RankDisplay rank={row.rank} /></td>
      <td>{row.isNew ? <span className="entryLabel">新入榜</span> : <RankDelta delta={row.delta} />}</td>
      <td title={row.sevenDayDelta === null ? "有效市场日不足，暂无法计算 7D 趋势。" : undefined}><RankDelta delta={row.sevenDayDelta} comparisonLabel="较 7 个有效市场日前" /></td>
      <td className="numberCell">{formatPrice(row.price)}</td>
      <td className="numberCell">{formatDeal(row)}</td>
      <td className="numberCell">{formatCompactNumber(row.reviews)}</td>
      <td><span className="presenceBadge">{row.presencePercent === null ? "—" : `${row.presenceDays}/${row.presenceWindowDays} · ${row.presencePercent}%`}</span></td>
    </tr>)}</tbody></table></div> : <div className="emptyState"><span aria-hidden="true">✓</span><div><h3>{emptyReason ? "当前市场暂无完整数据" : "没有匹配产品"}</h3><p>{emptyReason ?? "调整关键词或筛选条件后重试。"}</p></div></div>}
  </>;
}
