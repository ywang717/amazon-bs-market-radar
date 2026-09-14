"use client";

import { useMemo, useState } from "react";
import { formatCompactNumber, formatDeal, formatPrice, formatRating, type ProductIntelligenceRow } from "@/lib/ui-intelligence";
import { serializeMarketContext, type MarketContext as MarketContextValue } from "@/lib/market-context";
import { MarketContext } from "../components/MarketContext";
import { ProductIdentity } from "../components/ProductIdentity";
import { RankDelta, RankDisplay } from "../components/RankDisplay";

type Group = {
  key: string;
  label: string;
  marketDate: string;
  validMarketDates: string[];
  rows: ProductIntelligenceRow[];
  baselineDate: string | null;
};

function DealBadge({ row }: { row: ProductIntelligenceRow }) {
  const label = formatDeal(row);
  return <span className="dealBadge" title={label === "优惠信息待确认" ? "Amazon 页面存在较高参考价差，建议人工确认优惠信息。" : undefined}>{label}</span>;
}

export function RankingExplorer({ group, context }: { group: Group; context: MarketContextValue }) {
  const [query, setQuery] = useState("");
  const [limit, setLimit] = useState(30);
  const rows = useMemo(() => group.rows.filter((row) => row.rank <= limit && `${row.title} ${row.asin} ${row.brand ?? ""}`.toLowerCase().includes(query.toLowerCase())), [group, query, limit]);

  return <>
    <MarketContext marketDate={group.marketDate} validMarketDates={group.validMarketDates} context={context} page="rankings" />
    <div className="rankingToolbar">
      <div className="rankingScopeLabel" aria-label="当前榜单市场">{group.label}</div>
      <div className="filterBar"><label>搜索产品或 ASIN<input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="输入产品、品牌或 ASIN" /></label><label>排名范围<select value={limit} onChange={(event) => setLimit(Number(event.target.value))}><option value="10">Top 10</option><option value="20">Top 20</option><option value="30">Top 30</option></select></label><span>{rows.length} 条结果</span></div>
    </div>
    <div className="rankingSurface tableScroll"><table className="rankingTable v2RankingTable"><thead><tr><th>产品</th><th>排名</th><th>1D变化{group.baselineDate ? <span className="columnHint" title={`上一有效市场日 ${group.baselineDate}`}>ⓘ</span> : null}</th><th>价格</th><th>星级</th><th>评论数</th><th>优惠</th></tr></thead><tbody>{rows.map((row) => <tr key={row.asin}>
      <td><ProductIdentity asin={row.asin} title={row.title} type={row.productType} brand={row.brand} href={`/products/${row.asin}?${serializeMarketContext(context, { date: group.marketDate })}`} /></td>
      <td><RankDisplay rank={row.rank} /></td>
      <td>{row.isNew ? <span className="entryLabel">新入榜</span> : <RankDelta delta={row.delta} />}</td>
      <td className="numberCell">{formatPrice(row.price)}</td>
      <td className="numberCell">{formatRating(row.rating)}</td>
      <td className="numberCell">{formatCompactNumber(row.reviews)}</td>
      <td className="numberCell"><DealBadge row={row} /></td>
    </tr>)}</tbody></table></div>
  </>;
}
