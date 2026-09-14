import type { Metadata } from "next";
import { loadLiveDashboard } from "@/lib/live-dashboard-data";
import { MarketContext } from "../components/MarketContext";
import { PageHeader } from "../components/PageHeader";
import { DashboardDataNotices } from "../components/DashboardDataNotices";
import { buildAnalyticalCategory, buildClassificationCoverage } from "@/lib/ui-intelligence";
import { marketContextLabels, resolvePageMarketContext } from "@/lib/market-context";

export const metadata: Metadata = { title: "数据状态" };
export const dynamic = "force-dynamic";

export default async function DataStatusPage({ searchParams }: { searchParams?: Promise<Record<string, string | string[] | undefined>> }) {
  const query = searchParams ? await searchParams : {};
  const { context } = resolvePageMarketContext("data_status", query);
  const labels = marketContextLabels(context);
  const data = await loadLiveDashboard({ marketDate: typeof query.date === "string" ? query.date : undefined });
  const rawCategory = data.categoryRows.find((row) => row.key === context.category)!;
  const category = buildAnalyticalCategory(rawCategory, data.productMetadata, context);
  const ready = rawCategory.quality.complete;
  const latestSnapshotComplete = rawCategory.latestSnapshotComplete;
  const classification = buildClassificationCoverage(rawCategory.observations, data.productMetadata);
  const contextDays = category.history ?? [];
  const items = [
    ["最近 Snapshot", data.latestSnapshotDate, data.observedAt],
    ["最近有效市场日", rawCategory.marketDate, "当前分析使用的完整市场日"],
    ["完整市场日", String(rawCategory.completeMarketDays ?? 0), `${labels.category} 的有效市场日`],
    ["Top30 完整度", `${rawCategory.latestSnapshotObservationCount} / 30`, latestSnapshotComplete ? "完整" : "不完整；分析继续使用最近有效市场日"],
    ["当前分析样本", String(category.observations.length), `${labels.segment}分群`],
    ["价格覆盖率", `${rawCategory.priceCoverage.percent}%`, `${rawCategory.priceCoverage.present} / ${rawCategory.priceCoverage.total}`],
    ["星级覆盖率", `${rawCategory.ratingCoverage.percent}%`, `${rawCategory.ratingCoverage.present} / ${rawCategory.ratingCoverage.total}`],
    ["评论数覆盖率", `${rawCategory.reviewsCoverage.percent}%`, `${rawCategory.reviewsCoverage.present} / ${rawCategory.reviewsCoverage.total}`],
    ["分类覆盖率", `${classification.percent}%`, `${classification.classified} / ${classification.total} 已可靠分类`],
    ["未分类商品", String(classification.unknown), "保留在原始榜单，不进入整机分析"],
    ["分析就绪", ready ? "是" : "否", ready ? "当前市场日通过完整性校验" : "需要完整 Top30"],
    ["证据充分度", data.evidence, "公开证据优先"],
  ];

  return <>
    <MarketContext marketDate={rawCategory.marketDate} validMarketDates={rawCategory.validMarketDates} context={context} page="data_status" />
    <PageHeader eyebrow="数据质量" title="数据状态" description="技术完整性、字段覆盖与分析就绪信息集中在这里。" />
    <DashboardDataNotices source={data.source} metadataAvailable={data.metadataAvailable} />
    <section className="statusCardGrid">{items.map(([label, value, note]) => <article className="statusCard" key={label}><span>{label}</span><strong>{value}</strong><p>{note}</p></article>)}</section>
    <section className="coverageSurface">
      <div className="sectionHeading"><div><h2>数据覆盖情况</h2><p>{labels.category} · {labels.segment}</p></div><span className={latestSnapshotComplete ? "healthLabel" : "healthLabel warning"}>{latestSnapshotComplete ? "● 数据健康" : "● 最新 Snapshot 不完整"}</span></div>
      <div className="coverageTimeline" aria-label="当前市场历史数据质量">{contextDays.map((day) => <span className="complete" title={`${day.marketDate} · 完整`} key={day.marketDate}><i />{day.marketDate.slice(5)}</span>)}</div>
      <p>{contextDays.length} 个当前类目的完整有效市场日；不完整市场日不会被用于比较。</p>
    </section>
    <p className="methodologyPrompt">需要了解有效市场日、证据充分度与覆盖率口径？ <a href="/methodology" target="_top">查看方法说明 →</a></p>
  </>;
}
