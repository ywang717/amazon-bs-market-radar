import { env } from "cloudflare:workers";
import { validateSellerIntelligenceBundle, validateSellerIntelligenceReport, type SellerIntelligenceReport } from "@/lib/seller-intelligence-contract";
import { authorizeSyncRequest } from "@/lib/sync-auth";
import { ensureSchema, getD1 } from "@/lib/d1";
import { storeCategoryReport, validateCategoryReportEnvelope } from "@/lib/scoped-report-sync";

export async function POST(request: Request) {
  if (!authorizeSyncRequest(request, env.SYNC_SECRET as string | undefined)) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return Response.json({ error: "invalid_json" }, { status: 400 });
  }

  if (payload && typeof payload === "object" && "reports" in payload) {
    if ("categoryKey" in payload) {
      const scoped = validateCategoryReportEnvelope(payload, validateSellerIntelligenceReport);
      if (!scoped) return Response.json({ error: "invalid_category_report_bundle" }, { status: 400 });
      const db = getD1();
      await ensureSchema(db);
      return storeCategoryReport(db, "seller_intelligence_reports", scoped.report, scoped.receiptSha256);
    }
    const validatedBundle = validateSellerIntelligenceBundle(payload);
    if (!validatedBundle.ok) {
      return Response.json({ error: "invalid_seller_intelligence_bundle" }, { status: 400 });
    }

    try {
      const db = getD1();
      await ensureSchema(db);
      const first = validatedBundle.bundle.reports[0];
      const rawReceipt = (payload as { receiptSha256?: unknown }).receiptSha256;
      if (first.reportKind === "daily" && rawReceipt !== undefined) {
        if (typeof rawReceipt !== "string" || !/^[a-f0-9]{64}$/i.test(rawReceipt)) {
          return Response.json({ error: "invalid_seller_intelligence_bundle" }, { status: 400 });
        }
        return await storeDailySellerIntelligenceBundle(db, validatedBundle.bundle.reports, rawReceipt.toLowerCase());
      }
      return await storeSellerIntelligenceBundle(db, validatedBundle.bundle.reports);
    } catch {
      return Response.json({ error: "sync_unavailable" }, { status: 503 });
    }
  }

  const validated = validateSellerIntelligenceReport(payload);
  if (!validated.ok) return Response.json({ error: "invalid_seller_intelligence_report" }, { status: 400 });

  try {
    const db = getD1();
    await ensureSchema(db);
    return await storeSellerIntelligenceReport(db, validated.report);
  } catch {
    return Response.json({ error: "sync_unavailable" }, { status: 503 });
  }
}

async function storeDailySellerIntelligenceBundle(db: D1Database, reports: SellerIntelligenceReport[], receiptSha256: string) {
  const marketDate = reports[0].marketDate;
  const now = new Date().toISOString();
  const incomingRows = reports.map((_, index) => `${index === 0 ? "SELECT" : "UNION ALL SELECT"} ? AS key, ? AS report_kind, ? AS profile, ? AS market_date, ? AS category_key, ? AS generated_at, ? AS generator_version, ? AS content_sha256, ? AS content_json, ? AS imported_at`).join(" ");
  const keyPlaceholders = reports.map(() => "?").join(", ");
  const guardedUpsert = `INSERT INTO seller_intelligence_reports (key, report_kind, profile, market_date, category_key, generated_at, generator_version, content_sha256, content_json, imported_at)
    WITH existing_cohort AS (
      SELECT key, generated_at, generator_version, json_valid(content_json) AS content_valid,
        CASE
          WHEN json_valid(content_json) THEN
            CASE
              WHEN json_type(content_json, '$.receiptSha256') = 'text'
                THEN lower(json_extract(content_json, '$.receiptSha256'))
              ELSE NULL
            END
          ELSE NULL
        END AS receipt_sha256
      FROM seller_intelligence_reports
      WHERE report_kind = 'daily' AND profile = 'seller_alert' AND market_date = ?
    )
    SELECT incoming.key, incoming.report_kind, incoming.profile, incoming.market_date, incoming.category_key, incoming.generated_at, incoming.generator_version, incoming.content_sha256, incoming.content_json, incoming.imported_at
    FROM (${incomingRows}) AS incoming
    WHERE EXISTS (SELECT 1 FROM snapshots WHERE market_date = ? AND lower(receipt_sha256) = ?)
      AND (
        (SELECT COUNT(*) FROM existing_cohort) = 0
        OR (
          (SELECT COUNT(*) FROM existing_cohort) = 4
          AND (SELECT COUNT(*) FROM existing_cohort WHERE key IN (${keyPlaceholders})) = 4
          AND (
            (
              (SELECT COUNT(*) FROM existing_cohort WHERE receipt_sha256 IS NOT NULL AND length(receipt_sha256) = 64 AND receipt_sha256 NOT GLOB '*[^0-9a-f]*') = 4
              AND (SELECT COUNT(DISTINCT receipt_sha256) FROM existing_cohort) = 1
              AND (SELECT MAX(receipt_sha256) FROM existing_cohort) <> ?
            )
            OR (
              (SELECT COUNT(*) FROM existing_cohort WHERE receipt_sha256 IS NULL AND content_valid = 1) = 4
              AND (SELECT COUNT(DISTINCT generated_at) FROM existing_cohort) = 1
              AND (SELECT COUNT(DISTINCT generator_version) FROM existing_cohort) = 1
            )
          )
        )
      )
    ON CONFLICT(key) DO UPDATE SET report_kind=excluded.report_kind, profile=excluded.profile, market_date=excluded.market_date, category_key=excluded.category_key, generated_at=excluded.generated_at, generator_version=excluded.generator_version, content_sha256=excluded.content_sha256, content_json=excluded.content_json, imported_at=excluded.imported_at`;
  const values: unknown[] = [marketDate];
  for (const report of reports) {
    values.push(report.key, report.reportKind, report.profile, report.marketDate, report.categoryKey, report.generatedAt, report.generatorVersion, report.contentSha256, JSON.stringify({ ...report, receiptSha256 }), now);
  }
  values.push(marketDate, receiptSha256, ...reports.map((report) => report.key), receiptSha256);
  const result = await db.prepare(guardedUpsert).bind(...values).run();
  if (Number(result.meta?.changes ?? 0) === reports.length) {
    return Response.json({ status: "imported", reportCount: reports.length }, { status: 201 });
  }

  const snapshot = await db.prepare("SELECT receipt_sha256 FROM snapshots WHERE market_date = ?").bind(marketDate).first<{ receipt_sha256: string }>();
  if (!snapshot || snapshot.receipt_sha256.toLowerCase() !== receiptSha256) {
    return Response.json({ error: "snapshot_receipt_mismatch" }, { status: 409 });
  }
  const existing = await Promise.all(reports.map(async (report) => ({
    report,
    stored: await db.prepare("SELECT content_sha256, content_json FROM seller_intelligence_reports WHERE key = ?").bind(report.key).first<{ content_sha256: string; content_json: string }>(),
  })));
  const duplicate = existing.every(({ report, stored }) => {
    if (!stored || stored.content_sha256 !== report.contentSha256) return false;
    try {
      return String((JSON.parse(stored.content_json) as { receiptSha256?: unknown }).receiptSha256 ?? "").toLowerCase() === receiptSha256;
    } catch {
      return false;
    }
  });
  if (duplicate) return Response.json({ status: "duplicate", reportCount: reports.length });
  return Response.json({ error: "immutable_key_conflict" }, { status: 409 });
}

function sellerIntelligenceInsert(db: D1Database, report: SellerIntelligenceReport, importedAt: string) {
  return db
    .prepare(
      "INSERT INTO seller_intelligence_reports (key, report_kind, profile, market_date, category_key, generated_at, generator_version, content_sha256, content_json, imported_at) SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ? WHERE ? <> 'daily' OR NOT EXISTS (SELECT 1 FROM category_capture_receipts WHERE market_date = ?)",
    )
    .bind(
      report.key,
      report.reportKind,
      report.profile,
      report.marketDate,
      report.categoryKey,
      report.generatedAt,
      report.generatorVersion,
      report.contentSha256,
      JSON.stringify(report),
      importedAt,
      report.reportKind,
      report.marketDate,
    );
}

async function loadSellerIntelligenceHashes(db: D1Database, reports: SellerIntelligenceReport[]) {
  return Promise.all(reports.map(async (report) => ({
    report,
    canonical: await db
      .prepare("SELECT content_sha256 FROM seller_intelligence_reports WHERE key = ?")
      .bind(report.key)
      .first<{ content_sha256: string }>(),
  })));
}

async function storeSellerIntelligenceBundle(db: D1Database, reports: SellerIntelligenceReport[]) {
  const existing = await loadSellerIntelligenceHashes(db, reports);
  if (existing.some(({ canonical }) => canonical)) {
    if (existing.length === reports.length && existing.every(({ report, canonical }) => canonical?.content_sha256 === report.contentSha256)) {
      return Response.json({ status: "duplicate", reportCount: reports.length });
    }
    return Response.json({ error: "immutable_key_conflict" }, { status: 409 });
  }

  try {
    const importedAt = new Date().toISOString();
    const results = await db.batch(reports.map((report) => sellerIntelligenceInsert(db, report, importedAt)));
    if (results.some((result) => Number(result.meta?.changes ?? 0) === 0)) {
      return Response.json({ error: "snapshot_receipt_required" }, { status: 409 });
    }
    return Response.json({ status: "imported", reportCount: reports.length }, { status: 201 });
  } catch {
    const afterFailure = await loadSellerIntelligenceHashes(db, reports);
    if (afterFailure.every(({ report, canonical }) => canonical?.content_sha256 === report.contentSha256)) {
      return Response.json({ status: "duplicate", reportCount: reports.length });
    }
    if (afterFailure.some(({ canonical }) => canonical)) {
      return Response.json({ error: "immutable_key_conflict" }, { status: 409 });
    }
    throw new Error("Seller intelligence bundle storage failed");
  }
}

async function storeSellerIntelligenceReport(db: D1Database, report: SellerIntelligenceReport) {
  const inserted = await db
    .prepare(
      "INSERT OR IGNORE INTO seller_intelligence_reports (key, report_kind, profile, market_date, category_key, generated_at, generator_version, content_sha256, content_json, imported_at) SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ? WHERE ? <> 'daily' OR NOT EXISTS (SELECT 1 FROM category_capture_receipts WHERE market_date = ?)",
    )
    .bind(
      report.key,
      report.reportKind,
      report.profile,
      report.marketDate,
      report.categoryKey,
      report.generatedAt,
      report.generatorVersion,
      report.contentSha256,
      JSON.stringify(report),
      new Date().toISOString(),
      report.reportKind,
      report.marketDate,
    )
    .run();

  if ((inserted.meta?.changes ?? 0) > 0) {
    return Response.json({ status: "imported", key: report.key }, { status: 201 });
  }

  if (report.reportKind === "daily" && await db.prepare("SELECT 1 AS present FROM category_capture_receipts WHERE market_date = ? LIMIT 1").bind(report.marketDate).first()) {
    return Response.json({ error: "snapshot_receipt_required" }, { status: 409 });
  }

  const canonical = await db
    .prepare("SELECT content_sha256 FROM seller_intelligence_reports WHERE key = ?")
    .bind(report.key)
    .first<{ content_sha256: string }>();

  if (!canonical) {
    return Response.json({ error: "sync_unavailable" }, { status: 503 });
  }

  if (canonical.content_sha256 === report.contentSha256) {
    return Response.json({ status: "duplicate", key: report.key });
  }

  return Response.json({ error: "immutable_key_conflict" }, { status: 409 });
}
