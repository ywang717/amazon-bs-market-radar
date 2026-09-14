import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { loadLiveDashboard, loadLiveProduct } from "@/lib/live-dashboard-data";
import { readExplicitSpecificationsForProduct } from "@/lib/product-specs";
import type { ProductMetadata } from "@/lib/product-metadata";
import { isValidAsin } from "@/lib/public-validation";
import { buildAnalyticalCategory, buildProductRankTimeline, formatCompactNumber, formatDeal, formatExactNumber, formatPrice, formatRating, resolveProductTimelineStatus } from "@/lib/ui-intelligence";
import { filterAnalyticalMarket, resolvePageMarketContext, serializeMarketContext } from "@/lib/market-context";
import { MarketContext } from "../../components/MarketContext";
import { ProductIdentity } from "../../components/ProductIdentity";
import { QualityBadge } from "../../components/QualityBadge";
import { RankDisplay } from "../../components/RankDisplay";
import { TimelineEvent } from "../../components/TimelineEvent";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "产品详情" };

function productEvidenceRange(history: Array<{ marketDate: string }>) {
  const start = history[0]?.marketDate ?? "";
  const end = history.at(-1)?.marketDate ?? start;
  return start && end && start !== end ? `${start} 至 ${end}` : `市场日 ${end || start}`;
}

export default async function ProductPage({ params, searchParams }: { params: Promise<{ asin: string }>; searchParams?: Promise<Record<string, string | string[] | undefined>> }) {
  const { asin } = await params;
  const query = searchParams ? await searchParams : {};
  const { context } = resolvePageMarketContext("product_detail", query);
  if (!isValidAsin(asin)) notFound();
  const requestedDate = typeof query.date === "string" ? query.date : undefined;
  const [result, dashboard] = await Promise.all([loadLiveProduct(asin, { context, marketDate: requestedDate }), loadLiveDashboard({ marketDate: requestedDate })]);
  if (result.status === "not_found") notFound();

  const { current, category, history, bestRank, daysListed, evidence } = result.product;
  const productMetadata = (dashboard.productMetadata as ProductMetadata[]).find((row) => row.asin === current.asin) ?? null;
  const hasMetadata = productMetadata !== null;
  if (category.key !== context.category || (hasMetadata && filterAnalyticalMarket([current], dashboard.productMetadata as ProductMetadata[], context).length === 0)) notFound();
  const rawCategory = dashboard.categoryRows.find((row) => row.key === context.category)!;
  const analyticalCategory = buildAnalyticalCategory(rawCategory, dashboard.productMetadata, context);
  const analyticalHistory = analyticalCategory.history ?? [];
  const reliableHistory = hasMetadata && dashboard.metadataAvailable
    ? analyticalHistory
    : rawCategory.history ?? [];
  const timelineHistory = reliableHistory.length
    ? reliableHistory
    : [{ marketDate: rawCategory.marketDate, observations: [current] }];
  const timeline = buildProductRankTimeline(timelineHistory, current.asin);
  const timelineStatus = resolveProductTimelineStatus(timeline);
  const currentObservation = timelineStatus.currentObservation;
  const lastListedObservation = timelineStatus.lastListedObservation ?? current;
  const marketDate = rawCategory.marketDate;
  const explicitSpecs = readExplicitSpecificationsForProduct(category.key, productMetadata?.productType ?? "unknown", current.title);
  const delta = timelineStatus.delta;

  return <>
    <MarketContext marketDate={marketDate} validMarketDates={dashboard.categoryRows.find((row) => row.key === context.category)?.validMarketDates} context={context} page="product_detail" />
    {result.source === "seed_fallback" && <p className="sourceNotice" role="status">实时数据暂不可用，当前展示已验证回退数据。</p>}
    <header className="productDetailHeader">
      <ProductIdentity asin={current.asin} title={current.title} type={productMetadata?.productType ?? "unknown"} brand={productMetadata?.normalizedBrand ?? productMetadata?.rawBrand ?? null} />
      {currentObservation
        ? <div className="productCurrentStatus"><RankDisplay rank={currentObservation.rank} delta={delta} /><strong>{formatPrice(currentObservation.price)}</strong><span>{formatRating(currentObservation.rating)}</span><span>{formatCompactNumber(currentObservation.reviews)} 条评论</span></div>
        : <div className="productCurrentStatus"><strong>已退出 Top30</strong><span>当前排名 —</span><span>最后在榜 {timelineStatus.lastListedMarketDate ?? "—"}</span></div>}
      <a className="amazonLink" href={current.url} target="_blank" rel="noreferrer">查看 Amazon ↗</a>
    </header>

    <section className="dashboardGrid productTimelineGrid">
      <article className="panel wide trendPanel">
        <div className="panelHead"><div><h2>排名时间线</h2><p>纵轴已反转：顶部为 #1，底部为 #30</p></div><QualityBadge tone={daysListed >= 5 ? "good" : "warning"}>{daysListed} 个市场日</QualityBadge></div>
        <div className="rankChartWrap"><span className="top10ZoneLabel">TOP10</span><div className="singlePointChart"><div className="axis"><span>#1</span><span>#10</span><span>#20</span><span>#30</span></div><div className="chartArea multi rankTimelineArea"><div className="top10Zone" aria-hidden="true" /><svg className="rankTimelineSvg" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">{timeline.segments.filter((segment) => segment.length > 1).map((segment, index) => <polyline key={`segment-${index}`} points={segment.map((point) => `${point.xPercent},${point.yPercent}`).join(" ")} />)}</svg>{timeline.points.flatMap((row, index) => row.observation ? [<button type="button" className="historyPoint" aria-label={`${row.marketDate}，排名第 ${row.observation.rank}`} key={`${row.marketDate}-${row.observation.rank}-${index}`} style={{ top: `${row.yPercent}%`, left: `${row.xPercent}%` }} title={`${row.marketDate}\n排名 #${row.observation.rank}\n${row.delta === null || row.delta === 0 ? "—" : row.delta > 0 ? `↑${row.delta}` : `↓${Math.abs(row.delta)}`}\n${formatPrice(row.observation.price)}\n${formatExactNumber(row.observation.reviews)} Reviews`} />] : [])}</div></div><div className="rankTimelineDates" aria-hidden="true">{timeline.axisLabels.map((label) => <span key={label.marketDate} style={{ left: `${label.xPercent}%` }}>{label.marketDate.slice(5).replace("-", "/")}</span>)}</div></div>
        <ol className="srOnly rankHistoryAccessible" aria-label="排名历史数据">{timeline.points.flatMap((row, index) => row.observation ? [<li key={`accessible-${row.marketDate}-${row.observation.rank}-${index}`}>{row.marketDate}，排名第 {row.observation.rank}</li>] : [])}</ol>
      </article>
      <article className="panel productSnapshot"><h2>{currentObservation ? "当前状态" : `最后在榜观测（${timelineStatus.lastListedMarketDate ?? "—"}）`}</h2><dl><div><dt>历史最佳</dt><dd>#{bestRank}</dd></div><div><dt>有效在榜日</dt><dd>{daysListed}</dd></div><div><dt>证据充分度</dt><dd>{evidence}</dd></div><div><dt>优惠</dt><dd>{formatDeal(currentObservation ?? lastListedObservation)}</dd></div></dl></article>
    </section>

    <section className="productDetailLower">
      <article className="panel"><div className="panelHead"><div><h2>时间线事件</h2><p>只记录可验证的排名、价格和优惠变化</p></div></div><ul className="timelineEventList">{timeline.events.slice(-8).map((event, index) => <TimelineEvent kind={event.kind} date={event.marketDate} detail={event.detail} key={`${event.marketDate}-${event.kind}-${index}`} />)}</ul></article>
      <article className="panel detailList"><h2>在榜与评论</h2><dl><div><dt>市场日</dt><dd>{marketDate}</dd></div><div><dt>当前层级</dt><dd>{currentObservation ? currentObservation.rank <= 10 ? "Top10" : "Top30" : "已退出 Top30"}</dd></div><div><dt>星级</dt><dd>{currentObservation ? formatRating(currentObservation.rating) : "—"}</dd></div><div><dt>评论数</dt><dd>{currentObservation ? formatExactNumber(currentObservation.reviews) : "—"}</dd></div>{!currentObservation && <div><dt>最后在榜观测</dt><dd>{timelineStatus.lastListedMarketDate ?? "—"}</dd></div>}</dl><p>缺失字段不插值、不猜测。</p></article>
    </section>

    {explicitSpecs.length > 0 && <section className="panel detailList sellerObservationPanel">
      <div className="panelHead"><div><h2>产品事实</h2><p>只保留公开可验证事实；缺失字段不以数值代替。</p></div><QualityBadge tone="good">参数已明确</QualityBadge></div>
      <dl className="sellerEvidenceList"><div><dt>数据范围</dt><dd>{productEvidenceRange(history)}</dd></div><div><dt>样本量</dt><dd>{history.length} 条可验证历史观测</dd></div><div><dt>完整度</dt><dd>未单独判定（单商品页仅统计该 ASIN 的可验证历史观测）</dd></div><div><dt>证据充分度</dt><dd>{evidence}</dd></div><div><dt>非因果提示</dt><dd>仅描述可验证公开事实，不代表因果关系。</dd></div></dl>
      <dl className="sellerSpecList">{explicitSpecs.map((spec) => <div key={`${spec.label}-${spec.value}`}><dt>{spec.label}</dt><dd>{spec.value}</dd></div>)}</dl>
    </section>}
    <Link prefetch={false} href={`/products?${serializeMarketContext(context, { date: marketDate })}`} className="backLink">← 返回产品列表</Link>
  </>;
}
