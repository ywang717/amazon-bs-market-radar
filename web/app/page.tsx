import { loadLiveDashboard } from "@/lib/live-dashboard-data";
import { buildAnalyticalCategory, buildBrandMovement, buildBrandStructure, buildMarketSignals, buildMarketState, buildProductRows, buildWorthStudyingProducts, formatExactNumber, groupMarketSignals } from "@/lib/ui-intelligence";
import { ProductIdentity } from "./components/ProductIdentity";
import { RankDisplay } from "./components/RankDisplay";
import { EmptyState } from "./components/EmptyState";
import { MarketContext } from "./components/MarketContext";
import { MetricCard } from "./components/MetricCard";
import { SignalCard } from "./components/SignalCard";
import { DashboardDataNotices } from "./components/DashboardDataNotices";
import { marketContextLabels, resolvePageMarketContext } from "@/lib/market-context";
import { ContextLink } from "./components/ContextLink";

export const dynamic = "force-dynamic";

const stateLabels = { LOW: "低", MEDIUM: "中等", HIGH: "高" } as const;

export default async function Home({ searchParams }: { searchParams?: Promise<Record<string, string | string[] | undefined>> }) {
  const query = searchParams ? await searchParams : {};
  const { context } = resolvePageMarketContext("overview", query);
  const labels = marketContextLabels(context);
  const requestedDate = typeof query.date === "string" ? query.date : undefined;
  const data = await loadLiveDashboard({ marketDate: requestedDate });
  const rawCategory = data.categoryRows.find((row) => row.key === context.category)!;
  const category = buildAnalyticalCategory(rawCategory, data.productMetadata, context);
  const signals = buildMarketSignals({ categoryRows: [category], productMetadata: data.productMetadata });
  const signalGroups = groupMarketSignals(signals);
  const marketState = buildMarketState(category);
  const worthStudying = buildWorthStudyingProducts(buildProductRows({ observations: category.observations, comparison: category.comparison, metadata: data.productMetadata, history: category.history })).slice(0, 2);
  const brandMovement = buildBrandMovement({
    current: category.observations,
    previous: category.previousObservations ?? [],
    metadata: data.productMetadata,
  }).filter((row) => row.verified && row.delta !== 0).slice(0, 3);
  const highSignals = signals.filter(({ level }) => level === "high").length;
  const watchSignals = signals.filter(({ level }) => level === "watch").length;
  const displayedSignals = signalGroups.alerts.length ? signalGroups.alerts : signalGroups.activity;
  const brandStructure = buildBrandStructure(category.observations, data.productMetadata);
  const top3Share = brandStructure.top3Concentration;
  const marketSummary = !category.comparison.ready
    ? "当前市场日已载入，尚缺少可验证的上一市场日比较。"
    : marketState.volatility === "HIGH"
      ? `今天${labels.segment}市场波动较高，发现 ${highSignals} 个高优先级信号、${watchSignals} 个观察项和 ${signalGroups.activity.length} 条普通动态。`
    : highSignals || watchSignals
      ? `今天${labels.segment}市场发现 ${highSignals} 个高优先级信号、${watchSignals} 个观察项，另有 ${signalGroups.activity.length} 条普通动态。`
      : signalGroups.activity.length
        ? `${labels.segment}市场整体稳定，暂无高优先级异常，检测到 ${signalGroups.activity.length} 条普通市场变化。`
      : "今天市场整体较稳定，暂未检测到高优先级变化。";

  return <>
    <MarketContext marketDate={rawCategory.marketDate} validMarketDates={rawCategory.validMarketDates} context={context} page="overview" />
    <DashboardDataNotices source={data.source} metadataAvailable={data.metadataAvailable} />
    <header className="overviewHero">
      <div><p className="pageEyebrow">Daily Brief · {rawCategory.marketDate}</p><h1>{labels.category}</h1><p>{marketSummary}</p></div>
      <ContextLink href="/market" target="_top">查看市场状态 →</ContextLink>
    </header>

    <section className="metricCardGrid" aria-label="核心市场指标">
      <MetricCard value={highSignals} label="高优先级信号" detail={watchSignals ? `${watchSignals} 个观察项` : "暂无观察项"} tone={highSignals ? "danger" : "positive"} />
      <MetricCard value={category.comparison.ready ? category.comparison.entries ?? "—" : "—"} label="新入榜" detail="1D · 对比上一有效市场日" />
      <MetricCard value={marketState.top10Stability === null ? "—" : `${marketState.top10Stability}%`} label="Top10 稳定度（1D）" detail="1D · 头部阵容留存" tone="positive" />
      <MetricCard value={marketState.volatility ? stateLabels[marketState.volatility] : "—"} label="市场波动" detail={marketState.ready ? "基于平均绝对排名变动" : "等待有效比较日"} tone={marketState.volatility === "HIGH" ? "warning" : "neutral"} />
    </section>

    <section className="sectionBlock signalSection">
      <div className="sectionHeading"><div><h2>{signalGroups.alerts.length ? "今日需要关注" : "市场动态"}</h2><p>只展示当前市场中优先级最高的 5 条变化</p></div><ContextLink href="/market" target="_top">查看全部 →</ContextLink></div>
      {displayedSignals.length ? <div className="signalStack">
        <SignalCard signal={displayedSignals[0]} context={context} marketDate={rawCategory.marketDate} featured />
        {displayedSignals.length > 1 && <div className="secondarySignalGrid">{displayedSignals.slice(1, 5).map((signal) => <SignalCard signal={signal} context={context} marketDate={rawCategory.marketDate} key={`${signal.kind}-${signal.asin ?? signal.brand}`} />)}</div>}
      </div> : <EmptyState description="当前市场没有检测到高优先级变化，普通变化仍可在市场页面查看。" />}
    </section>

    {worthStudying.length > 0 && <section className="sectionBlock"><div className="sectionHeading"><h2>值得研究</h2><ContextLink href="/market">查看市场 →</ContextLink></div><div className="secondarySignalGrid">{worthStudying.map((row) => <article className="summarySurface" key={row.asin}><ProductIdentity asin={row.asin} title={row.title} brand={row.brand} type={row.productType} /><RankDisplay rank={row.rank} delta={row.delta} /><p>{formatExactNumber(row.reviews)} Reviews · 有效在榜日 {row.presenceDays}/{row.presenceWindowDays}</p><p>{row.reason} · 值得进一步研究</p><ContextLink href={`/products/${row.asin}`}>查看产品 →</ContextLink></article>)}</div></section>}

    <section className="overviewBottomGrid">
      <article className="summarySurface">
        <div className="sectionHeading"><div><h2>品牌变化</h2><p>Top30 席位变化 · 1D</p></div></div>
        {brandMovement.length ? <div className="movementList">{brandMovement.map((row) => <div key={row.brand}><b>{row.brand}</b><span>{row.previousSeats} → {row.currentSeats}</span><strong className={row.delta > 0 ? "positive" : "negative"}>{row.delta > 0 ? `+${row.delta}` : row.delta}</strong></div>)}</div> : <p className="mutedText">其余主要品牌席位稳定。</p>}
        <ContextLink className="surfaceLink" href="/brands" target="_top">查看品牌 →</ContextLink>
      </article>
      <article className="summarySurface">
        <div className="sectionHeading"><div><h2>市场结构</h2><p>快速判断当前市场状态</p></div></div>
        <dl className="structureList">
          <div><dt>Top10 稳定度（1D）</dt><dd>{marketState.top10Stability === null ? "—" : `${marketState.top10Stability}%`}</dd></div>
          <div><dt>榜单更替</dt><dd>{marketState.turnover ? stateLabels[marketState.turnover] : "—"}</dd></div>
          <div><dt>前三品牌席位占比</dt><dd>{top3Share === null ? "—" : `${top3Share}%`}</dd></div>
        </dl>
        <ContextLink className="surfaceLink" href="/market" target="_top">查看市场 →</ContextLink>
      </article>
    </section>
  </>;
}
