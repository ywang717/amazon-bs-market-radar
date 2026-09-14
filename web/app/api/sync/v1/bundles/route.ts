import { env } from "cloudflare:workers";
import { authorizeSyncRequest, bundleId } from "@/lib/sync-auth";
import { validateSyncBundle } from "@/lib/sync-contract";
import { ensureSchema, getD1 } from "@/lib/d1";
import { buildProductMetadataBrandConflictGuardStatement, buildProductMetadataUpsertStatement, isProductMetadataBrandConflictError } from "@/lib/product-metadata-upsert";

export async function POST(request: Request) {
  if (!authorizeSyncRequest(request, env.SYNC_SECRET as string | undefined)) return Response.json({ error: "unauthorized" }, { status: 401 });
  let payload: Record<string, unknown>;
  try { payload = await request.json() as Record<string, unknown>; } catch { return Response.json({ error: "invalid_json" }, { status: 400 }); }
  const validated = validateSyncBundle(payload);
  if (!validated.ok) return Response.json({ error: "invalid_bundle", details: validated.errors }, { status: 400 });
  const id = bundleId({ receiptSha256: String(payload.receiptSha256) });
  const marketDate = String(payload.marketDate);
  const db = getD1();
  await ensureSchema(db);
  const duplicate = await db.prepare("SELECT market_date FROM snapshots WHERE receipt_sha256 = ?").bind(id).first<{ market_date: string }>();
  if (duplicate && duplicate.market_date !== marketDate) return Response.json({ status: "duplicate", marketDate: duplicate.market_date, bundleId: id });

  const now = new Date().toISOString();
  const statements: D1PreparedStatement[] = [];
  if (validated.productMetadata.length > 0) {
    statements.push(buildProductMetadataBrandConflictGuardStatement(db, validated.productMetadata));
  }
  // Lazily retain provenance for this day only; historical days are untouched.
  statements.push(db.prepare(`INSERT INTO category_capture_receipts (market_date, category_key, receipt_sha256, observed_at)
    SELECT c.market_date, c.category_key, s.receipt_sha256, s.observed_at
    FROM category_days c JOIN snapshots s ON s.market_date = c.market_date
    WHERE c.market_date = ?
    ON CONFLICT(market_date, category_key) DO NOTHING`).bind(marketDate));
  for (const category of validated.categories) {
    // Evaluated inside the same batch transaction, not a stale preflight SELECT.
    statements.push(db.prepare(`INSERT INTO market_sync_guard (guard_key, conflict)
      SELECT 'bundle', EXISTS (
        SELECT 1 FROM category_days c LEFT JOIN category_capture_receipts r
          ON r.market_date = c.market_date AND r.category_key = c.category_key
        WHERE c.market_date = ? AND c.category_key = ?
          AND ((c.complete = 1 AND ? = 0) OR julianday(r.observed_at) > julianday(?))
      ) ON CONFLICT(guard_key) DO UPDATE SET conflict = excluded.conflict`).bind(marketDate, category.key, category.quality.complete ? 1 : 0, String(payload.observedAt)));
    for (const table of ["observation_discounts", "observations", "category_days"]) {
      statements.push(db.prepare(`DELETE FROM ${table} WHERE market_date = ? AND category_key = ?`).bind(marketDate, category.key));
    }
    statements.push(db.prepare("INSERT INTO category_days (market_date, category_key, source_url, observation_count, complete, missing_ranks_json) VALUES (?, ?, ?, ?, ?, ?)").bind(marketDate, category.key, String(category.sourceUrl), category.quality.observationCount, category.quality.complete ? 1 : 0, JSON.stringify(category.quality.missingRanks)));
    for (const row of category.observations) {
      statements.push(db.prepare("INSERT INTO observations (market_date, category_key, rank, asin, title, url, price, rating, reviews) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)").bind(marketDate, category.key, row.rank, row.asin, row.title, row.url, row.price, row.rating, row.reviews));
      statements.push(db.prepare("INSERT INTO observation_discounts (market_date, category_key, rank, has_discount, discounts_json) VALUES (?, ?, ?, ?, ?)").bind(marketDate, category.key, row.rank, row.has_discount === null ? null : row.has_discount ? 1 : 0, JSON.stringify(row.discounts)));
    }
    statements.push(db.prepare(`INSERT INTO category_capture_receipts (market_date, category_key, receipt_sha256, observed_at)
      VALUES (?, ?, ?, ?) ON CONFLICT(market_date, category_key) DO UPDATE SET receipt_sha256 = excluded.receipt_sha256, observed_at = excluded.observed_at`)
      .bind(marketDate, category.key, id, String(payload.observedAt)));
  }
  statements.push(db.prepare("DELETE FROM snapshots WHERE market_date = ?").bind(marketDate));
  statements.push(db.prepare(`INSERT INTO snapshots (market_date, observed_at, receipt_sha256, public_status, complete_category_count, imported_at)
    SELECT ?, MAX(r.observed_at),
      CASE WHEN COUNT(DISTINCT r.receipt_sha256) = 1 AND COUNT(*) = 3 THEN MAX(r.receipt_sha256) ELSE 'mixed:' || ? END,
      CASE WHEN SUM(c.complete) = 3 THEN '已更新' ELSE '数据不完整' END, SUM(c.complete), ?
    FROM category_days c JOIN category_capture_receipts r ON r.market_date = c.market_date AND r.category_key = c.category_key
    WHERE c.market_date = ?`).bind(marketDate, marketDate, now, marketDate));
  for (const metadata of validated.productMetadata) {
    statements.push(buildProductMetadataUpsertStatement(db, metadata));
  }
  try {
    await db.batch(statements);
  } catch (error) {
    if (isProductMetadataBrandConflictError(error)) return Response.json({ error: "brand_metadata_conflict" }, { status: 409 });
    if (error instanceof Error && /market_sync_guard_check/.test(error.message)) return Response.json({ error: "category_snapshot_conflict" }, { status: 409 });
    throw error;
  }
  return Response.json({ status: "imported", marketDate, bundleId: id, observations: validated.categories.reduce((sum, category) => sum + category.observations.length, 0) }, { status: 201 });
}
