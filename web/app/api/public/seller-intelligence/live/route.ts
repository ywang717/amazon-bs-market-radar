import { buildLiveSellerIntelligence, liveCacheHeader, loadVerifiedLiveDashboardFromD1, parseSellerIntelligenceLiveQuery } from "@/lib/seller-intelligence";

export async function GET(request: Request) {
  const parsed = parseSellerIntelligenceLiveQuery(new URL(request.url));
  if (!parsed.ok) return Response.json({ error: parsed.error }, { status: 400 });

  try {
    const dashboard = await loadVerifiedLiveDashboardFromD1(parsed.date ?? undefined);
    const report = await buildLiveSellerIntelligence(dashboard, {
      profile: parsed.profile,
      categoryKey: parsed.category,
      context: parsed.context ?? undefined,
    });
    return Response.json(report, { headers: liveCacheHeader });
  } catch {
    return Response.json({ error: "unavailable" }, { status: 503 });
  }
}
