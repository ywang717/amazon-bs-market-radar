import { WorthStudying } from "../components/WorthStudying";
import type { Metadata } from "next";
import { loadLiveDashboard } from "@/lib/live-dashboard-data";
import { buildAnalyticalCategory, buildMarketSignals, buildMarketState, buildMarketTrend, buildProductRows, buildProductTypeStructure, buildReviewCompetition, buildWorthStudyingProducts, buildTwoDayComparison, buildRangeAnalysis, formatExactNumber, formatPercentage, formatPrice, groupMarketSignals, median } from "@/lib/ui-intelligence";
import { EmptyState } from "../components/EmptyState";
import { SignalCard } from "../components/SignalCard";
import { DashboardDataNotices } from "../components/DashboardDataNotices";
import { ProductIdentity, productTypeLabel } from "../components/ProductIdentity";
import { RankDelta, RankDisplay } from "../components/RankDisplay";
import { marketContextLabels, resolvePageMarketContext, serializeMarketContext, type MarketContext as MarketContextValue } from "@/lib/market-context";
import { WorkspaceShell } from "../components/WorkspaceShell";
import { DecisionHero } from "../components/DecisionHero";
import { EvidenceRail } from "../components/EvidenceRail";
import { ActionDock } from "../components/ActionDock";
import { RangeControls } from "./RangeControls";
import { RangeExportButtons } from "./RangeExportButtons";

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
  const history = (category.history ?? []).toSorted((a, b) => a.marketDate.localeCompare(b.marketDate));
  const analysisMode = query.analysis_mode === "compare" || query.analysis_mode === "range" ? String(query.analysis_mode) : "single";
  const compareDate = typeof query.compare_date === "string" ? query.compare_date : history.filter((day) => day.marketDate < raw.marketDate).at(-1)?.marketDate;
  const compare = analysisMode === "compare" ? buildTwoDayComparison(history.find((day) => day.marketDate === compareDate), history.find((day) => day.marketDate === raw.marketDate), data.productMetadata) : null;
  const rangeStart = typeof query.range_start === "string" ? query.range_start : history.at(-2)?.marketDate;
  const rangeEnd = typeof query.range_end === "string" ? query.range_end : raw.marketDate;
  const range = analysisMode === "range" ? buildRangeAnalysis(history, rangeStart ?? raw.marketDate, rangeEnd, data.productMetadata) : null;
  const trend = buildMarketTrend(category.history ?? [], windowDays, data.productMetadata);
  const state = buildMarketState(category);
  const signals = buildMarketSignals({ categoryRows: [category], productMetadata: data.productMetadata });
  const signalLevel = ["all", "high", "watch", "activity"].includes(String(query.signal_level)) ? String(query.signal_level) : "all";
  const signalKind = typeof query.signal_kind === "string" ? query.signal_kind : "all";
  const filteredSignals = signals.filter((signal) => (signalLevel === "all" || signal.level === signalLevel) && (signalKind === "all" || signal.kind === signalKind));
  const grouped = groupMarketSignals(filteredSignals);
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

  return <WorkspaceShell context={context} marketDate={raw.marketDate} validMarketDates={raw.validMarketDates} page="market" eyebrow={`${labels.category} · ${labels.segment}`} title="市场状态" description={`当前有效市场日 vs ${category.comparison.baselineDate ?? "上一有效市场日待补充"}。`}
    evidence={<EvidenceRail items={[{ label: "波动程度", value: state.volatility ? metricLabel[state.volatility] : "—", tone: state.volatility === "HIGH" ? "danger" : "good" }, { label: "Top10 稳定度", value: state.top10Stability === null ? "—" : `${state.top10Stability}%` }, { label: "榜单更替", value: state.turnover ? metricLabel[state.turnover] : "—" }, { label: sampleLabel, value: category.observations.length }]} />}
    actions={<ActionDock><a href={marketHref(context, raw.marketDate, "movers", windowDays)}>查看排名变化 →</a><a href={marketHref(context, raw.marketDate, "entrants", windowDays)}>查看入榜/出榜 →</a></ActionDock>}
  >
    <DashboardDataNotices source={data.source} metadataAvailable={data.metadataAvailable} />
    <DecisionHero title={state.volatility ? stateLabel[state.volatility] : "等待比较日"} summary={`${labels.category} · ${labels.segment} 当前市场状态`} tone={state.volatility === "HIGH" ? "danger" : state.volatility === "MEDIUM" ? "warning" : "positive"} />
    <dl className="srOnly"><dt>波动程度 ⓘ</dt><dd>{state.volatility ? metricLabel[state.volatility] : "—"}</dd><dt>整机样本 ⓘ</dt><dd>{category.observations.length}</dd></dl>

    {analysisMode === "compare" && <section className="sectionBlock analysisWorkspace"><div className="sectionHeading"><div><h2>自选两日比较</h2><p>比较两个真实有效市场日，不补造缺失值。</p></div></div>{compare?.ready ? <div className="marketOverviewGrid"><article className="summarySurface"><h3>{compare.startDate} → {compare.endDate}</h3><p>Top10 共同商品：{compare.top10.common} · Top30 共同商品：{compare.top30.common}</p><p>入榜 {compare.entries.length} · 出榜 {compare.exits.length}</p></article><article className="summarySurface"><h3>排名变化</h3>{compare.movers.slice(0, 8).map((row) => <p key={row.asin}><strong>{row.asin}</strong> {row.startRank} → {row.endRank} · {row.rankChange > 0 ? `上升 ${row.rankChange}` : row.rankChange < 0 ? `下降 ${Math.abs(row.rankChange)}` : "持平"}</p>)}</article></div> : <EmptyState description={compare?.reason ?? "请选择两个有效市场日。"} />}</section>}
    {analysisMode === "range" && <section className="sectionBlock analysisWorkspace"><RangeControls dates={history.map((day) => day.marketDate)} start={rangeStart ?? raw.marketDate} end={rangeEnd} /><div className="sectionHeading"><div><h2>区间分析</h2><p>只使用选定范围内实际存在的市场日，缺失点保留为空。</p></div>{range?.ready ? <RangeExportButtons products={range.products.map((row) => ({ asin: row.asin, title: row.title, startRank: row.startRank, endRank: row.endRank, rankChange: row.rankChange, presencePercent: row.presencePercent }))} marketTrend={range.marketTrend.map((row) => ({ ...row }))} start={range.summary.startDate ?? rangeStart ?? raw.marketDate} end={range.summary.endDate ?? rangeEnd} /> : null}</div>{range?.ready ? <><div className="rangeQuickLinks">最近有效日：{history.slice(-7).map((day) => <a href={`/market?${serializeMarketContext(context, { date: day.marketDate, view: "overview", analysis_mode: "range", range_start: history.slice(-7)[0].marketDate, range_end: day.marketDate })}`} key={day.marketDate}>{day.marketDate}</a>)}</div><div className="marketOverviewGrid"><article className="summarySurface"><h3>{range.summary.startDate} → {range.summary.endDate}</h3><p>有效市场日 {range.summary.completeDays} · Top10 共同商品 {range.summary.top10Overlap ?? "—"} · Top30 共同商品 {range.summary.top30Common ?? "—"}</p></article><article className="summarySurface"><h3>产品趋势</h3>{range.products.slice(0, 8).map((row) => <p key={row.asin}><strong>{row.asin}</strong> {row.startRank ?? "—"} → {row.endRank ?? "—"} · 在榜 {row.presencePercent}%</p>)}</article></div><div className="tableScroll"><table><thead><tr><th>市场日</th><th>Top10 稳定度</th><th>入榜</th><th>出榜</th><th>平均排名变化</th></tr></thead><tbody>{range.marketTrend.map((row) => <tr key={row.marketDate}><td>{row.marketDate}</td><td>{row.top10Stability === null ? "—" : `${row.top10Stability}%`}</td><td>{row.entries ?? "—"}</td><td>{row.exits ?? "—"}</td><td>{row.averageAbsoluteMove ?? "—"}</td></tr>)}</tbody></table></div></> : <EmptyState description={range?.reason ?? "请选择两个有效市场日。"} />}</section>}

    <nav className="marketViewTabs" aria-label="市场分析视图">{views.map(([key, label]) => <a aria-current={view === key ? "page" : undefined} className={view === key ? "active" : ""} href={marketHref(context, raw.marketDate, key, windowDays)} key={key}>{label}</a>)}</nav>
    {view === "overview" && <section className="sectionBlock marketTrendSection"><div className="sectionHeading"><div><h2>{windowDays}D 市场趋势</h2><p>只使用有效市场日；与前一等长窗口比较。</p></div></div><div className="marketWindowBar"><span>趋势窗口</span>{windows.map((days) => <a aria-current={windowDays === days ? "true" : undefined} className={windowDays === days ? "active" : ""} href={marketHref(context, raw.marketDate, view, days)} key={days}>{days}D</a>)}<small>{trend.ready ? `${trend.previous.startDate}–${trend.previous.endDate} vs ${trend.current.startDate}–${trend.current.endDate}` : `需要 ${windowDays * 2} 个有效市场日`}</small></div><div className="marketOverviewGrid">
      <article className="summarySurface"><h2>Top10 稳定度（{windowDays}D）</h2><strong>{trend.ready ? `${formatPercentage(trend.metrics.top10Stability.current, 1)} ${trendDirection(trend.metrics.top10Stability.direction)}` : "—"}</strong><p>{windowDays}D 当前窗口 vs 前一等长窗口</p></article>
      <article className="summarySurface"><h2>市场更替</h2><strong>{trend.ready ? `${trend.metrics.turnover.current} ${trendDirection(trend.metrics.turnover.direction)}` : "—"}</strong><p>{windowDays}D 当前窗口 vs 前一等长窗口</p></article>
      <article className="summarySurface"><h2>Top3 品牌集中度</h2><strong>{trend.ready ? `${formatPercentage(trend.metrics.top3Concentration.current, 1)} ${trendDirection(trend.metrics.top3Concentration.direction)}` : "—"}</strong><p>按当前榜单席位，不代表销量份额。 <a href={`/brands?${serializeMarketContext(context, { date: raw.marketDate })}`}>查看品牌 →</a></p></article>
      <article className="summarySurface"><h2>价格中位数</h2><strong>{formatPrice(median(prices))}</strong><p>当前有效市场日 · {prices.length} 个价格样本</p><p>{windowDays}D 窗口末日：{trend.ready ? `${formatPrice(trend.metrics.medianPrice.current)} ${trendDirection(trend.metrics.medianPrice.direction)}（较前一等长窗口末日）` : "有效市场日不足 —"}</p></article>
    </div></section>}

    {view === "overview" && <section className="marketOverviewGrid marketDecisionGrid">
      <article className="summarySurface"><div className="sectionHeading"><div><h2>Amazon 原始 Top30 商品结构</h2><p>基于 Amazon 原始 Best Sellers 榜单进行产品类型标准化，不改变 Amazon 原始排名；此模块不受整机/配件分群筛选影响。</p></div></div><div className="tableScroll"><table><thead><tr><th>产品类型</th><th>当前席位</th>{typeTrends.map(({ windowDays }) => <th key={windowDays}>{windowDays}D</th>)}</tr></thead><tbody>{productTypeStructure.rows.map((row) => <tr key={row.productType}><td>{productTypeLabel(row.productType)}</td><td className="numberCell">{row.currentSeats}</td>{typeTrends.map((trend) => { const change = trend.rows.find(({ productType }) => productType === row.productType)?.seatChange ?? null; return <td className="numberCell" key={trend.windowDays} title={change === null ? "有效市场日不足，暂无法计算该窗口趋势。" : `较 ${trend.windowDays} 个有效市场日前的席位变化`}>{change === null || change === 0 ? "—" : change > 0 ? `+${change}` : change}</td>; })}</tr>)}</tbody></table></div><small>合计 {productTypeStructure.rows.reduce((sum, row) => sum + row.currentSeats, 0)} 席 · 含其他、未知与整机</small></article>
      <article className="summarySurface"><div className="sectionHeading"><div><h2>评论竞争</h2><p>仅描述当前榜单评论分布，不推断销量或因果。</p></div></div><dl className="compactMetricList"><div><dt>Top10 评论中位数</dt><dd>{formatExactNumber(reviewCompetition.top10Median)}</dd></div><div><dt>Top30 评论中位数</dt><dd>{formatExactNumber(reviewCompetition.top30Median)}</dd></div><div><dt>Top10 最低评论数</dt><dd>{formatExactNumber(reviewCompetition.top10Minimum)}</dd></div></dl></article>
    </section>}

    {view === "overview" && <WorthStudying rows={worthStudying} context={context} marketDate={raw.marketDate} baselineDate={category.comparison.baselineDate??null} completeDays={category.history?.length??0} updatedAt={data.observedAt} failed={data.source==="seed_fallback"} source="/market"/>}

    {view === "movers" && <section className="rankingSurface tableScroll"><div className="sectionHeading"><div><h2>排名变化 · 1D</h2><p>当前有效市场日与上一有效市场日之间的同一商品排名变化。</p></div></div><table><thead><tr><th>产品</th><th>排名</th><th>1D变化</th><th>价格</th></tr></thead><tbody>{(category.comparison.movers ?? []).map((row) => { const meta = metadataByAsin.get(row.asin); return <tr key={row.asin}><td><ProductIdentity asin={row.asin} title={row.title} brand={meta?.normalizedBrand} type={meta?.productType} href={`/products/${row.asin}?${serializeMarketContext(context, { date: raw.marketDate })}`} /></td><td><RankDisplay rank={row.rank} /></td><td><RankDelta delta={row.change} /></td><td className="numberCell">{formatPrice(row.price)}</td></tr>; })}</tbody></table></section>}

    {view === "entrants" && <section className="sectionBlock"><div className="sectionHeading"><div><h2>榜单边界事件 · 1D</h2><p>上一有效市场日至当前有效市场日的 Top30 边界变化。</p></div></div>{signals.some(({ kind }) => ["first_seen", "new_entry", "re_entry", "exit"].includes(kind)) ? <div className="marketSignalGrid">{signals.filter(({ kind }) => ["first_seen", "new_entry", "re_entry", "exit"].includes(kind)).map((signal) => <SignalCard signal={signal} context={context} marketDate={raw.marketDate} key={`${signal.kind}-${signal.asin}`} />)}</div> : <EmptyState description="当前有效市场日没有入榜或出榜事件。" />}</section>}

    {view === "overview" && <section className="sectionBlock"><div className="sectionHeading"><div><h2>预警摘要</h2><p>High 与 Watch 独立于普通 Activity。</p></div><a href={marketHref(context, raw.marketDate, "entrants", windowDays)}>查看事件流 →</a></div><div className="signalFilters" role="group" aria-label="市场信号筛选"><span>级别</span>{[["all","全部"],["high","High"],["watch","Watch"],["activity","Activity"]].map(([value,label]) => <a className={signalLevel === value ? "active" : ""} href={`/market?${serializeMarketContext(context, { date: raw.marketDate, view, window: String(windowDays), signal_level: value })}`} key={value}>{label}</a>)}<span>{filteredSignals.length} 条信号</span></div>{grouped.alerts.length ? <div className="marketSignalGrid">{grouped.alerts.slice(0, 5).map((signal, index) => <SignalCard signal={signal} context={context} marketDate={raw.marketDate} featured={index === 0} key={`${signal.kind}-${signal.asin ?? signal.brand}`} />)}</div> : <EmptyState description="当前筛选没有匹配信号。" />}</section>}
  </WorkspaceShell>;
}
