import { ensureSchema, getD1 } from "@/lib/d1";
import { productionMarketContextResolver, resolvePublicMarketQuery } from "@/lib/market-context";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const parsed = resolvePublicMarketQuery({
    marketplace: url.searchParams.get("marketplace"),
    category: url.searchParams.get("category"),
    segment: url.searchParams.get("segment"),
    page: "reports",
  }, productionMarketContextResolver);
  if (!parsed.ok) return Response.json({ error: parsed.error }, { status: 400 });
  try {
    const db = getD1(); await ensureSchema(db);
    const rows = await db.prepare("SELECT key, market_date, category_key, kind, title, byte_count FROM reports WHERE category_key = ? ORDER BY market_date DESC, kind, category_key").bind(parsed.context.category).all();
    return Response.json({ reports: rows.results }, { headers: { "cache-control": "public, max-age=300" } });
  } catch { return Response.json({ reports: [] }); }
}
