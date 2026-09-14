import type { Metadata } from "next";
import { loadLiveDashboard } from "@/lib/live-dashboard-data";
import { PageHeader } from "../components/PageHeader";
import { DashboardDataNotices } from "../components/DashboardDataNotices";
import { RankingExplorer } from "./RankingExplorer";
import { buildAnalyticalCategory, buildProductRows } from "@/lib/ui-intelligence";
import { marketContextLabels, resolvePageMarketContext } from "@/lib/market-context";

export const metadata: Metadata = { title: "榜单" };
export const dynamic = "force-dynamic";

export default async function RankingsPage({ searchParams }: { searchParams?: Promise<Record<string, string | string[] | undefined>> }) {
  const query = searchParams ? await searchParams : {};
  const { context } = resolvePageMarketContext("rankings", query);
  const labels = marketContextLabels(context);
  const requestedDate = typeof query.date === "string" ? query.date : undefined;
  const data = await loadLiveDashboard({ marketDate: requestedDate, preferLatestSnapshot: !requestedDate });
  const rawCategory = data.categoryRows.find((row) => row.key === context.category)!;
  const category = buildAnalyticalCategory(rawCategory, data.productMetadata, context);
  return <>
    <PageHeader eyebrow="Amazon 畅销榜" title="Top30 榜单" description={`${labels.category} · ${labels.segment}；“全部榜单”保留 Amazon 原始 Top30，细分分群仅显示已有可信分类的商品。`} />
    <DashboardDataNotices source={data.source} metadataAvailable={data.metadataAvailable} />
    <RankingExplorer context={context} group={{
      key: category.key,
      label: `${labels.category} · ${labels.segment}`,
      marketDate: rawCategory.marketDate,
      validMarketDates: rawCategory.validMarketDates,
      baselineDate: category.comparison.baselineDate ?? null,
      rows: buildProductRows({ observations: category.observations, comparison: category.comparison, metadata: data.productMetadata }),
    }} />
  </>;
}
