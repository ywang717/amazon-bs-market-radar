import { loadAnalyticalOverview } from "@/lib/live-dashboard-data";
import { parseMarketContext } from "@/lib/market-context";
import { buildAnalyticalCategory, buildClassificationCoverage, buildMarketSignals } from "@/lib/ui-intelligence";

export async function GET(request: Request) {
  const parsed = parseMarketContext(new URL(request.url));
  if (!parsed.ok) return Response.json({ error: parsed.error }, { status: 400 });

  try {
    const requestedDate = new URL(request.url).searchParams.get("date") ?? undefined;
    const { dashboard, rawObservationCount, analyticalObservations } = await loadAnalyticalOverview(parsed.context, { marketDate: requestedDate });
    const selectedCategory = dashboard.categoryRows.find(({ key }) => key === parsed.context.category)!;
    const classificationCoverage = buildClassificationCoverage(selectedCategory.observations, dashboard.productMetadata);
    const analyticalCategory = buildAnalyticalCategory(selectedCategory, dashboard.productMetadata, parsed.context);
    const marketSignals = buildMarketSignals({ categoryRows: [analyticalCategory], productMetadata: dashboard.productMetadata });
    const publicDashboard = {
      ...Object.fromEntries(Object.entries(dashboard).filter(([key]) => key !== "source" && key !== "categoryRows" && key !== "productMetadata")),
      categoryRows: dashboard.categoryRows.map((row) => Object.fromEntries(
        Object.entries(row).filter(([key]) => key !== "categoryDayPresent"),
      )),
    };
    return Response.json({ ...publicDashboard, marketDate: selectedCategory.marketDate, marketContext: parsed.context, rawObservationCount, analyticalObservations, classificationCoverage, marketSignals }, {
      headers: { "cache-control": "public, max-age=300" },
    });
  } catch (error) {
    console.error("overview_failed", error);
    return Response.json({ error: "unavailable" }, { status: 503 });
  }
}
