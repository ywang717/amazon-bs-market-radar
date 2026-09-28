import { ensureSchema, getD1 } from "@/lib/d1";
import { productionMarketContextResolver, resolvePublicMarketQuery } from "@/lib/market-context";
import { filterReportRecords, parseReportKindFilter } from "@/lib/reports-view";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const parsed = resolvePublicMarketQuery({
    marketplace: url.searchParams.get("marketplace"),
    category: url.searchParams.get("category"),
    segment: url.searchParams.get("segment"),
    page: "reports",
  }, productionMarketContextResolver);
  if (!parsed.ok) return Response.json({ error: parsed.error }, { status: 400 });
  const kind = parseReportKindFilter(url.searchParams.get("kind"));
  try {
    const db = getD1(); await ensureSchema(db);
    const rows = await db.prepare("SELECT key, market_date, category_key, segment_key, kind, title, byte_count FROM reports WHERE category_key = ? AND (segment_key = ? OR segment_key IS NULL) ORDER BY market_date DESC, kind, category_key").bind(parsed.context.category, parsed.context.segment).all();
    return Response.json({ reports: filterReportRecords(rows.results as import("@/lib/reports-view").ReportRecord[], kind) }, { headers: { "cache-control": "public, max-age=300" } });
  } catch {
    return Response.json({ error: "report_archive_unavailable", message: "报告归档暂时不可用，请稍后重试。" }, { status: 503 });
  }
}
