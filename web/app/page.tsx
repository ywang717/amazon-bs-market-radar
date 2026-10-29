import { loadLiveDashboard } from "@/lib/live-dashboard-data";
import { buildAnalyticalCategory, buildBrandMovement, buildBrandStructure, buildMarketSignals, buildMarketState, buildProductRows, buildWorthStudyingProducts, formatExactNumber, groupMarketSignals } from "@/lib/ui-intelligence";
import { ProductIdentity } from "./components/ProductIdentity";
import { RankDisplay } from "./components/RankDisplay";
import { EmptyState } from "./components/EmptyState";
import { WorkspaceShell } from "./components/WorkspaceShell";
import { DecisionHero } from "./components/DecisionHero";
import { TrendPanel } from "./components/TrendPanel";
import { EvidenceRail } from "./components/EvidenceRail";
import { ActionDock } from "./components/ActionDock";
import { SignalCard } from "./components/SignalCard";
import { DashboardDataNotices } from "./components/DashboardDataNotices";
import { marketContextLabels, resolvePageMarketContext, serializeMarketContext } from "@/lib/market-context";
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

  return <WorkspaceShell context={context} marketDate={rawCategory.marketDate} validMarketDates={rawCategory.validMarketDates} page="overview" eyebrow={`Daily Brief · ${rawCategory.marketDate}`} title={labels.category} description={marketSummary}
    evidence={<EvidenceRail items={[{ label: "数据更新", value: data.observedAt ? new Date(data.observedAt).toLocaleString("zh-CN", { hour12: false }) : "暂无" }, { label: "完整市场日", value: category.history?.length ?? 0 }, { label: "数据状态", value: data.source === "seed_fallback" ? "部分数据" : "可用", tone: data.source === "seed_fallback" ? "warning" : "good" }]} />}
    actions={<ActionDock><ContextLink href="/market" target="_top">查看市场状态 →</ContextLink><ContextLink href="/rankings" target="_top">查看榜单 →</ContextLink><ContextLink href="/reports" target="_top">打开报告 →</ContextLink></ActionDock>}
  >
    <DashboardDataNotices source={data.source} metadataAvailable={data.metadataAvailable} />
    <DecisionHero className="dashboardCommandHero" title={marketState.volatility === "HIGH" ? "市场波动较高" : "今日市场判断"} summary={marketSummary} tone={highSignals ? "danger" : watchSignals ? "warning" : "positive"}>
      <ContextLink href="/market" target="_top">查看市场状态 →</ContextLink>
    </DecisionHero>

    <TrendPanel title="趋势与状态" subtitle="先看市场方向，再看证据和行动" metrics={[{ label: "High", value: highSignals, detail: watchSignals ? `${watchSignals} 个 Watch` : "暂无 Watch", }, { label: "新入榜", value: category.comparison.ready ? category.comparison.entries ?? "—" : "—", detail: "1D · 对比上一有效市场日" }, { label: "Top10", value: marketState.top10Stability === null ? "—" : `${marketState.top10Stability}%`, detail: "1D 稳定度" }, { label: "波动", value: marketState.volatility ? stateLabels[marketState.volatility] : "—", detail: marketState.ready ? "平均绝对排名变动" : "等待比较日" }]} />

    <section className="sectionBlock signalSection">
      <div className="sectionHeading"><div><h2>{signalGroups.alerts.length ? "今日需要关注" : "市场动态"}</h2><p>只展示当前市场中优先级最高的 5 条变化</p></div><ContextLink href="/market" target="_top">查看全部 →</ContextLink></div>
      {displayedSignals.length ? <div className="signalStack">
        <SignalCard signal={displayedSignals[0]} context={context} marketDate={rawCategory.marketDate} featured />
        {displayedSignals.length > 1 && <div className="secondarySignalGrid">{displayedSignals.slice(1, 5).map((signal) => <SignalCard signal={signal} context={context} marketDate={rawCategory.marketDate} key={`${signal.kind}-${signal.asin ?? signal.brand}`} />)}</div>}
      </div> : <EmptyState description="当前市场没有检测到高优先级变化，普通变化仍可在市场页面查看。" />}
    </section>

    {worthStudying.length > 0 && <section className="sectionBlock dashboardEvidenceActions"><div className="sectionHeading"><h2>值得研究</h2><ContextLink href="/market">查看市场 →</ContextLink></div><div className="secondarySignalGrid">{worthStudying.map((row) => <article className="summarySurface" key={row.asin}><ProductIdentity asin={row.asin} title={row.title} brand={row.brand} type={row.productType} /><RankDisplay rank={row.rank} delta={row.delta} /><p>{formatExactNumber(row.reviews)} Reviews · 有效在榜日 {row.presenceDays}/{row.presenceWindowDays}</p><p><strong>为什么入选：</strong>{row.reason}</p><p><strong>数据依据：</strong>{rawCategory.marketDate} 市场日 · 比较日 {category.comparison.baselineDate??"不足"}</p><p><strong>证据缺口：</strong>需求、竞争、差异化及销售障碍仍需人工核验。</p><p>研究优先级不代表成交概率或销量预测。</p><ContextLink href={`/products/${row.asin}?returnTo=${encodeURIComponent("/?"+serializeMarketContext(context,{date:rawCategory.marketDate}))}`} target="_top">查看产品 →</ContextLink></article>)}</div></section>}

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
  </WorkspaceShell>;
}
