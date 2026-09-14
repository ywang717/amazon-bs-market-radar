import {
  fallbackCacheHeader,
  listSellerIntelligenceReports,
  liveCacheHeader,
  parseSellerIntelligenceListQuery,
} from "@/lib/seller-intelligence";

export async function GET(request: Request) {
  const parsed = parseSellerIntelligenceListQuery(new URL(request.url));
  if (!parsed.ok) return Response.json({ error: parsed.error }, { status: 400 });

  try {
    const reports = await listSellerIntelligenceReports({
      profile: parsed.profile,
      category: parsed.category,
      date: parsed.date,
    });
    return Response.json({ reports }, { headers: liveCacheHeader });
  } catch {
    return Response.json({ reports: [] }, { headers: fallbackCacheHeader });
  }
}
