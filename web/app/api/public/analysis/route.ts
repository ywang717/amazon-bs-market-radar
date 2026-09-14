import { categories } from "@/lib/catalog";
import { ensureSchema, getD1 } from "@/lib/d1";
import { validateMarketContext } from "@/lib/market-context";

const marketDate = /^\d{4}-\d{2}-\d{2}$/;

export async function GET(request: Request) {
  const url = new URL(request.url);
  const kind = url.searchParams.get("kind");
  const category = url.searchParams.get("category");
  const segment = url.searchParams.get("segment");
  const date = url.searchParams.get("date");
  if (kind && kind !== "daily" && kind !== "weekly") return Response.json({ error: "invalid_kind" }, { status: 400 });
  if (category && !categories.some(({ key }) => key === category)) return Response.json({ error: "invalid_category" }, { status: 400 });
  if (segment && (!category || !validateMarketContext({ marketplace: "US", category, segment }).ok)) return Response.json({ error: "unsupported_market_context" }, { status: 400 });
  if (date && !marketDate.test(date)) return Response.json({ error: "invalid_date" }, { status: 400 });
  try {
    const clauses: string[] = []; const values: string[] = [];
    if (kind) { clauses.push("report_kind = ?"); values.push(kind); }
    if (category) { clauses.push("category_key = ?"); values.push(category); }
    if (date) { clauses.push("market_date = ?"); values.push(date); }
    const where = clauses.length ? ` WHERE ${clauses.join(" AND ")}` : "";
    const db = getD1(); await ensureSchema(db);
    const rows = await db.prepare(`SELECT key, report_kind, market_date, category_key, generated_at, generator_version, content_sha256 FROM analysis_reports${where} ORDER BY market_date DESC, report_kind, category_key LIMIT 100`).bind(...values).all();
    return Response.json({ reports: rows.results }, { headers: { "cache-control": "public, max-age=300" } });
  } catch { return Response.json({ reports: [] }, { headers: { "cache-control": "public, max-age=60" } }); }
}
