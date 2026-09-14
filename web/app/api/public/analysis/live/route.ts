import type { CategoryKey } from "@/lib/catalog";
import { buildLiveAnalysisReport } from "@/lib/live-analysis";
import { loadLiveDashboard } from "@/lib/live-dashboard-data";
import { productionMarketContextResolver, resolvePublicMarketQuery, type MarketContext } from "@/lib/market-context";
import { buildAnalyticalCategory } from "@/lib/ui-intelligence";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const kind = url.searchParams.get("kind") ?? "daily";
  const category = url.searchParams.get("category");
  const segment = url.searchParams.get("segment");
  if (kind !== "daily" && kind !== "weekly") return Response.json({ error: "invalid_kind" }, { status: 400 });
  if (category && !productionMarketContextResolver.categoryByKey.has(category)) return Response.json({ error: "invalid_category" }, { status: 400 });
  const validatedContext = category && segment
    ? resolvePublicMarketQuery({ marketplace: "US", category, segment, page: "alerts" }, productionMarketContextResolver)
    : null;
  if (segment && (!category || !validatedContext?.ok)) return Response.json({ error: "unsupported_market_context" }, { status: 400 });
  try {
    const dashboard = await loadLiveDashboard({ marketDate: url.searchParams.get("date") ?? undefined });
    const context: MarketContext | null = validatedContext?.ok ? validatedContext.context as MarketContext : null;
    const categoryRows = context
      ? dashboard.categoryRows
        .filter((row) => row.key === context.category)
        .map((row) => buildAnalyticalCategory(row, dashboard.productMetadata, context))
      : dashboard.categoryRows;
    const selectedMarketDate = categoryRows[0]?.marketDate ?? dashboard.marketDate;
    const report = await buildLiveAnalysisReport(
      { ...dashboard, marketDate: selectedMarketDate, categoryRows },
      { reportKind: kind, categoryKey: category as CategoryKey | null },
    );
    return Response.json(report, { headers: { "cache-control": "public, max-age=300" } });
  } catch { return Response.json({ error: "unavailable" }, { status: 503 }); }
}
