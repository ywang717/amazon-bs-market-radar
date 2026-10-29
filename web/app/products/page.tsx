import type { Metadata } from "next";
import { loadLiveDashboard } from "@/lib/live-dashboard-data";
import { buildAnalyticalCategory, buildProductRows } from "@/lib/ui-intelligence";
import { WorkspaceShell } from "../components/WorkspaceShell";
import { EvidenceRail } from "../components/EvidenceRail";
import { ActionDock } from "../components/ActionDock";
import { ProductBrowser } from "./ProductBrowser";
import { DashboardDataNotices } from "../components/DashboardDataNotices";
import { marketContextLabels, resolvePageMarketContext } from "@/lib/market-context";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "产品" };

export default async function ProductsPage({ searchParams }: { searchParams?: Promise<Record<string, string | string[] | undefined>> }) {
  const query = searchParams ? await searchParams : {};
  const { context } = resolvePageMarketContext("products", query);
  const labels = marketContextLabels(context);
  const data = await loadLiveDashboard({ marketDate: typeof query.date === "string" ? query.date : undefined });
  const rawCategory = data.categoryRows.find((row) => row.key === context.category)!;
  const category = buildAnalyticalCategory(rawCategory, data.productMetadata, context);
  const rows = buildProductRows({ observations: category.observations, comparison: category.comparison, metadata: data.productMetadata, history: category.history });

  return <WorkspaceShell context={context} marketDate={rawCategory.marketDate} validMarketDates={rawCategory.validMarketDates} page="products" eyebrow="产品表现" title="产品" description={`搜索和分析 ${labels.category} · ${labels.segment} 中的产品表现。`}
    evidence={<EvidenceRail items={[{ label: "当前市场日", value: rawCategory.marketDate }, { label: "可验证商品", value: category.observations.length }, { label: "完整市场日", value: category.history?.length ?? 0 }, { label: "7D 趋势", value: category.history && category.history.length >= 8 ? "可用" : "积累中", tone: category.history && category.history.length >= 8 ? "good" : "warning" }]} />}
    actions={<ActionDock><a href={`/rankings?date=${rawCategory.marketDate}&category=${context.category}&segment=${context.segment}`}>查看榜单 →</a><a href={`/market?date=${rawCategory.marketDate}&category=${context.category}&segment=${context.segment}`}>查看趋势 →</a></ActionDock>}
  >
    <DashboardDataNotices source={data.source} metadataAvailable={data.metadataAvailable} />
    <ProductBrowser rows={rows} context={context} marketDate={rawCategory.marketDate} emptyReason={category.observations.length ? undefined : "当前市场没有可验证的完整榜单数据；这不是筛选无结果，请查看数据状态。"} />
  </WorkspaceShell>;
}
