import type { Metadata } from "next";
import { loadLiveDashboard } from "@/lib/live-dashboard-data";
import { buildAnalyticalCategory, buildMarketSignals, buildMarketState, buildMarketTrend, buildProductRows, buildProductTypeStructure, buildReviewCompetition, buildWorthStudyingProducts, formatExactNumber, formatPercentage, formatPrice, groupMarketSignals, median } from "@/lib/ui-intelligence";
import { EmptyState } from "../components/EmptyState";
import { MarketContext } from "../components/MarketContext";
import { SignalCard } from "../components/SignalCard";
import { DashboardDataNotices } from "../components/DashboardDataNotices";
import { ProductIdentity, productTypeLabel } from "../components/ProductIdentity";
import { RankDelta, RankDisplay } from "../components/RankDisplay";
import { marketContextLabels, resolvePageMarketContext, serializeMarketContext, type MarketContext as MarketContextValue } from "@/lib/market-context";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "市场" };

const stateLabel = { LOW: "稳定", MEDIUM: "温和波动", HIGH: "高波动" } as const;
const metricLabel = { LOW: "低", MEDIUM: "中", HIGH: "高" } as const;
const views = [["overview", "概览"], ["movers", "排名变化"], ["entrants", "入榜 / 出榜"]] as const;
const windows = [7, 30] as const;

function trendDirection(value: "up" | "down" | "neutral") {
  return value === "up" ? "↑" : value === "down" ? "↓" : "→";
}

function marketHref(context: MarketContextValue, marketDate: string, view: string, windowDays: number) {
  return `/market?${serializeMarketContext(context, { date: marketDate, view, ...(view === "overview" ? { window: String(windowDays) } : {}) })}`;
}

export default async function MarketPage({ searchParams }: { searchParams?: Promise<Record<string, string | string[] | undefined>> }) {
  const query = searchParams ? await searchParams : {};
  const view = views.some(([key]) => key === query.view) ? String(query.view) : "overview";
  const requestedWindow = Number(query.window ?? 7);
  const windowDays = windows.includes(requestedWindow as typeof windows[number]) ? requestedWindow : 7;
  const { context } = resolvePageMarketContext("market", query);
  const labels = marketContextLabels(context);
  const data = await loadLiveDashboard({ marketDate: typeof query.date === "string" ? query.date : undefined });
  const raw = data.categoryRows.find((row) => row.key === context.category)!;
  const category = buildAnalyticalCategory(raw, data.productMetadata, context);
  const trend = buildMarketTrend(category.history ?? [], windowDays, data.productMetadata);
  const state = buildMarketState(category);
  const signals = buildMarketSignals({ categoryRows: [category], productMetadata: data.productMetadata });
  const grouped = groupMarketSignals(signals);
  const productRows = buildProductRows({ observations: category.observations, comparison: category.comparison, metadata: data.productMetadata, history: category.history });
  const productTypeHistory = [
    ...(raw.history ?? []).filter(({ marketDate }) => marketDate !== raw.marketDate),
    { marketDate: raw.marketDate, observations: raw.observations },
  ];
  const productTypeStructure = buildProductTypeStructure(productTypeHistory, data.productMetadata, 7);
  const typeTrends = [1, 7, 30].map((days) => buildProductTypeStructure(productTypeHistory, data.productMetadata, days));
  const reviewCompetition = buildReviewCompetition(category.observations);
  const worthStudying = buildWorthStudyingProducts(productRows);
  const metadataByAsin = new Map(data.productMetadata.map((row) => [row.asin, row]));
  const prices = category.observations.map(({ price }) => price).filter((value): value is number => value !== null).toSorted((a, b) => a - b);
  const sampleLabel = context.segment === "all"
    ? context.category === "pressure_washer_accessories" ? "配件分析样本" : "分析样本"
    : `${labels.segment}样本`;

  return <>
    <MarketContext marketDate={raw.marketDate} validMarketDates={raw.validMarketDates} context={context} page="market" />
    <DashboardDataNotices source={data.source} metadataAvailable={data.metadataAvailable} />
    <header className="marketStatusHeader">
      <div><p className="pageEyebrow">{labels.category} · {labels.segment}</p><span>当前市场状态</span><h1>{state.volatility ? stateLabel[state.volatility] : "等待比较日"}</h1><p>当前有效市场日 vs {category.comparison.baselineDate ?? "上一有效市场日待补充"}。</p></div>
      <dl>
        <div><dt title="可比商品的平均绝对排名变动">波动程度 ⓘ</dt><dd>{state.volatility ? metricLabel[state.volatility] : "—"}</dd></div>
        <div><dt>Top10 稳定度（1D）</dt><dd>{state.top10Stability === null ? "—" : `${state.top10Stability}%`}</dd></div>
        <div><dt title="商品入榜与出榜事件合计">榜单更替 ⓘ</dt><dd>{state.turnover ? metricLabel[state.turnover] : "—"}</dd></div>
        <div><dt title="Amazon 原始 Top30 中符合当前分析分群的商品数量">{sampleLabel} ⓘ</dt><dd>{category.observations.length}</dd></div>
      </dl>
    </header>

    <nav className="marketViewTabs" aria-label="市场分析视图">{views.map(([key, label]) => <a aria-current={view === key ? "page" : undefined} className={view === key ? "active" : ""} href={marketHref(context, raw.marketDate, key, windowDays)} key={key}>{label}</a>)}</nav>
    {view === "overview" && <section className="sectionBlock marketTrendSection"><div className="sectionHeading"><div><h2>{windowDays}D 市场趋势</h2><p>只使用有效市场日；与前一等长窗口比较。</p></div></div><div className="marketWindowBar"><span>趋势窗口</span>{windows.map((days) => <a aria-current={windowDays === days ? "true" : undefined} className={windowDays === days ? "active" : ""} href={marketHref(context, raw.marketDate, view, days)} key={days}>{days}D</a>)}<small>{trend.ready ? `${trend.previous.startDate}–${trend.previous.endDate} vs ${trend.current.startDate}–${trend.current.endDate}` : `需要 ${windowDays * 2} 个有效市场日`}</small></div><div className="marketOverviewGrid">
      <article className="summarySurface"><h2>Top10 稳定度（{windowDays}D）</h2><strong>{trend.ready ? `${formatPercentage(trend.metrics.top10Stability.current, 1)} ${trendDirection(trend.metrics.top10Stability.direction)}` : "—"}</strong><p>{windowDays}D 当前窗口 vs 前一等长窗口</p></article>
      <article className="summarySurface"><h2>市场更替</h2><strong>{trend.ready ? `${trend.metrics.turnover.current} ${trendDirection(trend.metrics.turnover.direction)}` : "—"}</strong><p>{windowDays}D 当前窗口 vs 前一等长窗口</p></article>
      <article className="summarySurface"><h2>Top3 品牌集中度</h2><strong>{trend.ready ? `${formatPercentage(trend.metrics.top3Concentration.current, 1)} ${trendDirection(trend.metrics.top3Concentration.direction)}` : "—"}</strong><p>按当前榜单席位，不代表销量份额。 <a href={`/brands?${serializeMarketContext(context, { date: raw.marketDate })}`}>查看品牌 →</a></p></article>
      <article className="summarySurface"><h2>价格中位数</h2><strong>{formatPrice(median(prices))}</strong><p>当前有效市场日 · {prices.length} 个价格样本</p><p>{windowDays}D 窗口末日：{trend.ready ? `${formatPrice(trend.metrics.medianPrice.current)} ${trendDirection(trend.metrics.medianPrice.direction)}（较前一等长窗口末日）` : "有效市场日不足 —"}</p></article>
    </div></section>}

    {view === "overview" && <section className="marketOverviewGrid marketDecisionGrid">
      <article className="summarySurface"><div className="sectionHeading"><div><h2>Top30 商品结构</h2><p>基于 Amazon 原始 Best Sellers 榜单进行产品类型标准化，不改变 Amazon 原始排名。</p></div></div><div className="tableScroll"><table><thead><tr><th>产品类型</th><th>当前席位</th>{typeTrends.map(({ windowDays }) => <th key={windowDays}>{windowDays}D</th>)}</tr></thead><tbody>{productTypeStructure.rows.map((row) => <tr key={row.productType}><td>{productTypeLabel(row.productType)}</td><td className="numberCell">{row.currentSeats}</td>{typeTrends.map((trend) => { const change = trend.rows.find(({ productType }) => productType === row.productType)?.seatChange ?? null; return <td className="numberCell" key={trend.windowDays} title={change === null ? "有效市场日不足，暂无法计算该窗口趋势。" : `较 ${trend.windowDays} 个有效市场日前的席位变化`}>{change === null || change === 0 ? "—" : change > 0 ? `+${change}` : change}</td>; })}</tr>)}</tbody></table></div><small>合计 {productTypeStructure.rows.reduce((sum, row) => sum + row.currentSeats, 0)} 席 · 含其他、未知与整机</small></article>
      <article className="summarySurface"><div className="sectionHeading"><div><h2>评论竞争</h2><p>仅描述当前榜单评论分布，不推断销量或因果。</p></div></div><dl className="compactMetricList"><div><dt>Top10 评论中位数</dt><dd>{formatExactNumber(reviewCompetition.top10Median)}</dd></div><div><dt>Top30 评论中位数</dt><dd>{formatExactNumber(reviewCompetition.top30Median)}</dd></div><div><dt>Top10 最低评论数</dt><dd>{formatExactNumber(reviewCompetition.top10Minimum)}</dd></div></dl></article>
    </section>}

    {view === "overview" && <section className="sectionBlock"><div className="sectionHeading"><div><h2>值得研究</h2><p>基于低评论与可解释的排名变化筛选，仅用于后续人工研究。</p></div></div>{worthStudying.length ? <div className="rankingSurface tableScroll"><table><thead><tr><th>产品</th><th>排名</th><th>1D变化</th><th>评论数</th><th>筛选原因</th></tr></thead><tbody>{worthStudying.map((row) => <tr key={row.asin}><td><ProductIdentity asin={row.asin} title={row.title} brand={row.brand} type={row.productType} href={`/products/${row.asin}?${serializeMarketContext(context, { date: raw.marketDate })}`} /></td><td><RankDisplay rank={row.rank} /></td><td><RankDelta delta={row.delta} /></td><td className="numberCell">{formatExactNumber(row.reviews)}</td><td>{row.reason}</td></tr>)}</tbody></table></div> : <EmptyState description="当前没有同时满足低评论与显著排名上升条件的商品。" />}</section>}

    {view === "movers" && <section className="rankingSurface tableScroll"><div className="sectionHeading"><div><h2>排名变化 · 1D</h2><p>当前有效市场日与上一有效市场日之间的同一商品排名变化。</p></div></div><table><thead><tr><th>产品</th><th>排名</th><th>1D变化</th><th>价格</th></tr></thead><tbody>{(category.comparison.movers ?? []).map((row) => { const meta = metadataByAsin.get(row.asin); return <tr key={row.asin}><td><ProductIdentity asin={row.asin} title={row.title} brand={meta?.normalizedBrand} type={meta?.productType} href={`/products/${row.asin}?${serializeMarketContext(context, { date: raw.marketDate })}`} /></td><td><RankDisplay rank={row.rank} /></td><td><RankDelta delta={row.change} /></td><td className="numberCell">{formatPrice(row.price)}</td></tr>; })}</tbody></table></section>}

    {view === "entrants" && <section className="sectionBlock"><div className="sectionHeading"><div><h2>榜单边界事件 · 1D</h2><p>上一有效市场日至当前有效市场日的 Top30 边界变化。</p></div></div>{signals.some(({ kind }) => ["first_seen", "new_entry", "re_entry", "exit"].includes(kind)) ? <div className="marketSignalGrid">{signals.filter(({ kind }) => ["first_seen", "new_entry", "re_entry", "exit"].includes(kind)).map((signal) => <SignalCard signal={signal} context={context} marketDate={raw.marketDate} key={`${signal.kind}-${signal.asin}`} />)}</div> : <EmptyState description="当前有效市场日没有入榜或出榜事件。" />}</section>}

    {view === "overview" && <section className="sectionBlock"><div className="sectionHeading"><div><h2>预警摘要</h2><p>High 与 Watch 独立于普通 Activity。</p></div><a href={marketHref(context, raw.marketDate, "entrants", windowDays)}>查看事件流 →</a></div>{grouped.alerts.length ? <div className="marketSignalGrid">{grouped.alerts.slice(0, 5).map((signal, index) => <SignalCard signal={signal} context={context} marketDate={raw.marketDate} featured={index === 0} key={`${signal.kind}-${signal.asin ?? signal.brand}`} />)}</div> : <EmptyState description="当前市场没有 High 或 Watch 信号。" />}</section>}
  </>;
}
