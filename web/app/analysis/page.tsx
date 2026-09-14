import type { Metadata } from "next";
import Link from "next/link";
import { SellerIntelligenceCenter, parseAnalysisSearchParams } from "./SellerIntelligenceCenter";
import { AnalysisCenter } from "./AnalysisCenter";
import { PageHeader } from "../components/PageHeader";
import { MarketContext } from "../components/MarketContext";
import { loadLiveDashboard } from "@/lib/live-dashboard-data";
import { marketContextLabels, resolvePageMarketContext, serializeMarketContext } from "@/lib/market-context";

export const metadata: Metadata = { title: "智能报告" };
export const dynamic = "force-dynamic";

export default async function AnalysisPage({
  searchParams,
}: {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
}) {
  const resolvedSearchParams = searchParams ? await searchParams : {};
  const { context } = resolvePageMarketContext("alerts", resolvedSearchParams);
  const labels = marketContextLabels(context);
  const state = { ...parseAnalysisSearchParams(resolvedSearchParams), categoryKey: context.category };
  const data = await loadLiveDashboard({ marketDate: typeof resolvedSearchParams.date === "string" ? resolvedSearchParams.date : undefined });
  const category = data.categoryRows.find((row) => row.key === context.category)!;
  const sellerWorkspace = typeof resolvedSearchParams.workspace === "string" || Array.isArray(resolvedSearchParams.workspace);
  const modeHref = (params: Record<string, string> = {}) => `/analysis?${serializeMarketContext(context, { date: category.marketDate, ...params })}`;
  return (
    <>
      <MarketContext marketDate={category.marketDate} validMarketDates={category.validMarketDates} context={context} page="alerts" />
      <PageHeader
        eyebrow="证据优先分析"
        title={sellerWorkspace ? "在线卖家情报中心" : "智能报告中心"}
        description={`${labels.category} · ${labels.segment}；${sellerWorkspace ? "经营预警、竞争观察与已验证归档统一展示，只输出公开可核查的描述性观察。" : "保留实时解读与历史智能报告，并提供卖家经营情报工作入口。"}`}
      />
      <nav className="tabs analysisCenterModeNav" aria-label="智能报告工作区">
        <Link prefetch={false} aria-current={!sellerWorkspace ? "page" : undefined} className={!sellerWorkspace ? "active" : ""} href={modeHref()}>实时解读 / 历史归档</Link>
        <Link prefetch={false} aria-current={sellerWorkspace && state.workspace === "seller_alert" ? "page" : undefined} className={sellerWorkspace && state.workspace === "seller_alert" ? "active" : ""} href={modeHref({ workspace: "seller_alert" })}>经营预警</Link>
        <Link prefetch={false} aria-current={sellerWorkspace && state.workspace === "competition_strategy" ? "page" : undefined} className={sellerWorkspace && state.workspace === "competition_strategy" ? "active" : ""} href={modeHref({ workspace: "competition_strategy" })}>竞争观察</Link>
        <Link prefetch={false} aria-current={sellerWorkspace && state.workspace === "archive" ? "page" : undefined} className={sellerWorkspace && state.workspace === "archive" ? "active" : ""} href={modeHref({ workspace: "archive", profile: "seller_alert" })}>卖家历史归档</Link>
      </nav>
      {sellerWorkspace ? <SellerIntelligenceCenter {...state} context={context} marketDate={category.marketDate} /> : <AnalysisCenter context={context} marketDate={category.marketDate} />}
    </>
  );
}
