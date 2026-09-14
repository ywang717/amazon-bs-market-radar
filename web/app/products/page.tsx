import type { Metadata } from "next";
import { loadLiveDashboard } from "@/lib/live-dashboard-data";
import { buildAnalyticalCategory, buildProductRows } from "@/lib/ui-intelligence";
import { MarketContext } from "../components/MarketContext";
import { PageHeader } from "../components/PageHeader";
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

  return <>
    <MarketContext marketDate={rawCategory.marketDate} validMarketDates={rawCategory.validMarketDates} context={context} page="products" />
    <PageHeader eyebrow="" title="产品" description={`搜索和分析 ${labels.category} · ${labels.segment} 中的产品表现。`} />
    <DashboardDataNotices source={data.source} metadataAvailable={data.metadataAvailable} />
    <ProductBrowser rows={rows} context={context} marketDate={rawCategory.marketDate} emptyReason={category.observations.length ? undefined : "当前市场没有可验证的完整榜单数据；这不是筛选无结果，请查看数据状态。"} />
  </>;
}
