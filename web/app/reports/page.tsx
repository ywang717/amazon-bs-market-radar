import type { Metadata } from "next";
import { PageHeader } from "../components/PageHeader";
import { ReportsArchive } from "./ReportsArchive";
import { loadLiveDashboard } from "@/lib/live-dashboard-data";
import { marketContextLabels, resolvePageMarketContext, serializeMarketContext } from "@/lib/market-context";
import { MarketContext } from "../components/MarketContext";
import { buildAnalyticalCategory, buildBrandMovement, buildBrandStructure, buildMarketSignals, buildMarketState, buildProductRows, buildProductTypeStructure, buildWorthStudyingProducts, formatExactNumber, productDisplayName } from "@/lib/ui-intelligence";
import { SignalCard } from "../components/SignalCard";
import { EmptyState } from "../components/EmptyState";
import { ProductIdentity, productTypeLabel } from "../components/ProductIdentity";
import { RankDelta, RankDisplay } from "../components/RankDisplay";

export const metadata: Metadata = { title: "报告" };

export const dynamic = "force-dynamic";

export default async function ReportsPage({ searchParams }: { searchParams?: Promise<Record<string, string | string[] | undefined>> }) {
  const query = searchParams ? await searchParams : {};
  const { context } = resolvePageMarketContext("reports", query);
  const labels = marketContextLabels(context);
  const data = await loadLiveDashboard({ marketDate: typeof query.date === "string" ? query.date : undefined });
  const category = data.categoryRows.find((row) => row.key === context.category)!;
  const analytical = buildAnalyticalCategory(category, data.productMetadata, context);
  const signals = buildMarketSignals({ categoryRows: [analytical], productMetadata: data.productMetadata });
  const high = signals.filter(({ level }) => level === "high");
  const watch = signals.filter(({ level }) => level === "watch");
  const activity = signals.filter(({ level }) => level === "activity");
  const noSignals = high.length === 0 && watch.length === 0 && activity.length === 0;
  const marketState = buildMarketState(analytical);
  const brandStructure = buildBrandStructure(analytical.observations, data.productMetadata);
  const productRows = buildProductRows({ observations: analytical.observations, comparison: analytical.comparison, metadata: data.productMetadata, history: analytical.history });
  const worthStudying = buildWorthStudyingProducts(productRows);
  const productTypeHistory = [
    ...(category.history ?? []).filter(({ marketDate }) => marketDate !== category.marketDate),
    { marketDate: category.marketDate, observations: category.observations },
  ];
  const productTypeStructure = buildProductTypeStructure(productTypeHistory, data.productMetadata, 7);
  const brandMovements = analytical.comparison.ready
    ? buildBrandMovement({ current: analytical.observations, previous: analytical.previousObservations ?? [], metadata: data.productMetadata })
      .filter(({ verified, delta }) => verified && delta !== 0)
      .slice(0, 5)
    : [];
  const metadataByAsin = new Map(data.productMetadata.map((row) => [row.asin, row]));
  const largestBrand = brandStructure.rows.find(({ brand }) => brand !== "其他" && brand !== "Unknown");
  const largestMove = analytical.comparison.movers?.toSorted((left, right) => right.absoluteMove - left.absoluteMove).find(({ absoluteMove }) => absoluteMove > 0);
  const summary = !analytical.comparison.ready
    ? `当前已有 ${analytical.history?.length ?? 0} 个完整市场日，尚缺少可验证比较日。`
    : `${marketState.volatility === "HIGH" ? `今日${labels.segment}市场波动较高。` : `今日${labels.segment}市场整体稳定。`} ${marketState.top10Stability === null ? "Top10 稳定度待补充。" : `Top10 稳定度为 ${marketState.top10Stability}%。`} High ${high.length} · Watch ${watch.length} · 市场动态 ${activity.length}。${largestBrand ? ` ${largestBrand.brand} 当前拥有最多 Top30 席位（${largestBrand.seats} 席）。` : ""}${largestMove ? ` 最大排名变化为 ${productDisplayName(largestMove.title, metadataByAsin.get(largestMove.asin)?.normalizedBrand ?? null, 42)} ${largestMove.absoluteMove} 位。` : ""}`;
  const analysisHref = (workspace?: string) => `/analysis?${serializeMarketContext(context, { date: category.marketDate, ...(workspace ? { workspace } : {}) })}`;
  return <>
    <MarketContext marketDate={category.marketDate} validMarketDates={category.validMarketDates} context={context} page="reports" />
    <PageHeader eyebrow="每日市场简报" title="报告" description={`${labels.category} · ${labels.segment} 的实时市场解读、经营预警、竞争观察与已验证报告归档。`} />
    <section className="panel reportMarketSummary" aria-label="市场摘要"><h2>市场摘要</h2><p>{summary}</p></section>
    <section className="reportSummary" aria-label="日报摘要"><article className="panel"><span>市场日期</span><strong>{category.marketDate}</strong><small>{labels.category} · {labels.segment}</small></article><article className="panel"><span>High</span><strong>{high.length}</strong><small>优先关注</small></article><article className="panel"><span>Watch</span><strong>{watch.length}</strong><small>持续观察</small></article><article className="panel"><span>市场动态</span><strong>{activity.length}</strong><small>普通市场变化</small></article></section>
    {noSignals && <section className="sectionBlock"><EmptyState description="今日暂无 High / Watch / Activity 市场变化。" /></section>}
    {high.length > 0 && <section className="sectionBlock"><div className="sectionHeading"><div><h2>High</h2><p>需要优先注意的已验证变化</p></div></div><div className="marketSignalGrid">{high.map((signal) => <SignalCard signal={signal} context={context} marketDate={category.marketDate} key={`high-${signal.kind}-${signal.asin ?? signal.brand}`} />)}</div></section>}
    {watch.length > 0 && <section className="sectionBlock"><div className="sectionHeading"><div><h2>Watch</h2><p>值得持续观察的变化，最多展示 5 条</p></div></div><div className="marketSignalGrid">{watch.slice(0, 5).map((signal) => <SignalCard signal={signal} context={context} marketDate={category.marketDate} key={`watch-${signal.kind}-${signal.asin ?? signal.brand}`} />)}</div></section>}
    {worthStudying.length > 0 && <section className="sectionBlock"><div className="sectionHeading"><div><h2>值得研究</h2><p>低评论且排名显著上升的商品，仅作为人工研究入口。</p></div></div><div className="rankingSurface tableScroll"><table><thead><tr><th>产品</th><th>排名</th><th>1D变化</th><th>评论数</th><th>筛选原因</th></tr></thead><tbody>{worthStudying.map((row) => <tr key={row.asin}><td><ProductIdentity asin={row.asin} title={row.title} brand={row.brand} type={row.productType} href={`/products/${row.asin}?${serializeMarketContext(context, { date: category.marketDate })}`} /></td><td><RankDisplay rank={row.rank} /></td><td><RankDelta delta={row.delta} /></td><td className="numberCell">{formatExactNumber(row.reviews)}</td><td>{row.reason}</td></tr>)}</tbody></table></div></section>}
    <section className="reportInsightGrid">
      <article className="summarySurface"><div className="sectionHeading"><div><h2>细分市场变化</h2><p>当前 Product Type 结构与 7D 席位变化。</p></div></div><div className="movementList">{productTypeStructure.rows.map((row) => <div key={row.productType}><b>{productTypeLabel(row.productType)}</b><span>{row.currentSeats} 席</span><strong>{row.seatChange === null ? "—" : row.seatChange > 0 ? `↑${row.seatChange}` : row.seatChange < 0 ? `↓${Math.abs(row.seatChange)}` : "—"}</strong></div>)}</div><small>{productTypeStructure.trendReady ? "7D 有效市场日席位变化" : "有效市场日不足，暂不显示 7D 变化"}</small></article>
      <article className="summarySurface"><div className="sectionHeading"><div><h2>品牌变化</h2><p>只展示上一有效市场日至当前日发生变化的已验证品牌。</p></div></div>{brandMovements.length ? <div className="movementList">{brandMovements.map((row) => <div key={row.brand}><b>{row.brand}</b><span>{row.previousSeats} → {row.currentSeats} 席</span><strong>{row.delta > 0 ? `↑${row.delta}` : `↓${Math.abs(row.delta)}`}</strong></div>)}</div> : <p>当前没有已验证的品牌席位变化。</p>}</article>
    </section>
    {activity.length > 0 && <details className="panel reportActivity"><summary>今日另外记录 {activity.length} 条普通市场动态</summary><div className="marketSignalGrid">{activity.map((signal) => <SignalCard signal={signal} context={context} marketDate={category.marketDate} key={`activity-${signal.kind}-${signal.asin ?? signal.brand}`} />)}</div></details>}
    <details className="panel signalEvidence"><summary>证据与方法</summary><p>信号只比较当前日与上一有效市场日；失败或不完整抓取不参与比较。High、Watch 与 Activity 来自全站唯一 Signal Engine，页面只做展示筛选。</p><p>建议对价格、优惠、评论与详情页变化进行人工确认；缺失字段不以 0 代替。</p></details>
    <section className="reportHubGrid">
      <a href={analysisHref()} target="_top"><span>01</span><h2>智能报告</h2><p>实时解读与历史归档</p><b>进入 →</b></a>
      <a href={analysisHref("seller_alert")} target="_top"><span>02</span><h2>经营预警</h2><p>高优先级 / 观察变化与人工核查项</p><b>进入 →</b></a>
      <a href={analysisHref("competition_strategy")} target="_top"><span>03</span><h2>竞争观察</h2><p>基于充分证据的描述性市场事实</p><b>进入 →</b></a>
    </section>
    <div className="sectionHeading reportArchiveHeading"><div><h2>已验证报告归档</h2><p>只有已验证 PDF 才提供下载</p></div><button className="selectButton">全部报告⌄</button></div>
    <ReportsArchive context={context} marketDate={category.marketDate} />
  </>;
}
