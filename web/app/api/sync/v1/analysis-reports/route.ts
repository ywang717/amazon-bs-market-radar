import { env } from "cloudflare:workers";
import { authorizeSyncRequest } from "@/lib/sync-auth";
import { validateAnalysisReport, type AnalysisReport } from "@/lib/analysis-report-contract";
import { ensureSchema, getD1 } from "@/lib/d1";
import { storeCategoryReport, validateCategoryReportEnvelope } from "@/lib/scoped-report-sync";

type ReceiptAnalysisReport = AnalysisReport & { receiptSha256: string };
type StoredAnalysisReport = { content_sha256: string; content_json: string };

const reportScopes = ["overview", "pressure_washers", "sump_pumps", "pressure_washer_accessories"] as const;

function validateDailyReportBundle(payload: unknown): ReceiptAnalysisReport[] | null {
  if (!payload || typeof payload !== "object") return null;
  const rawReports = (payload as { reports?: unknown }).reports;
  if (!Array.isArray(rawReports) || rawReports.length !== reportScopes.length) return null;
  const reports: ReceiptAnalysisReport[] = [];
  for (const rawReport of rawReports) {
    const validated = validateAnalysisReport(rawReport);
    const receiptSha256 = rawReport && typeof rawReport === "object" ? (rawReport as { receiptSha256?: unknown }).receiptSha256 : null;
    if (!validated.ok || typeof receiptSha256 !== "string" || !/^[a-f0-9]{64}$/i.test(receiptSha256)) return null;
    reports.push({ ...validated.report, receiptSha256: receiptSha256.toLowerCase() });
  }
  const marketDate = reports[0].marketDate;
  const receiptSha256 = reports[0].receiptSha256;
  if (reports.some((report) => report.reportKind !== "daily" || report.marketDate !== marketDate || report.receiptSha256 !== receiptSha256)) return null;
  for (const scope of reportScopes) {
    const expectedCategory = scope === "overview" ? null : scope;
    const matches = reports.filter((report) => report.key === `daily/${marketDate}/${scope}.json` && report.categoryKey === expectedCategory);
    if (matches.length !== 1) return null;
  }
  return reports;
}

async function storeDailyReportBundle(payload: unknown) {
  const reports = validateDailyReportBundle(payload);
  if (!reports) return Response.json({ error: "invalid_analysis_report_bundle" }, { status: 400 });
  const db = getD1();
  await ensureSchema(db);
  const marketDate = reports[0].marketDate;
  const receiptSha256 = reports[0].receiptSha256;
  const now = new Date().toISOString();
  const incomingRows = reports.map((_, index) => `${index === 0 ? "SELECT" : "UNION ALL SELECT"} ? AS key, ? AS report_kind, ? AS market_date, ? AS category_key, ? AS generated_at, ? AS generator_version, ? AS content_sha256, ? AS content_json, ? AS imported_at`).join(" ");
  const placeholders = reportScopes.map(() => "?").join(", ");
  const guardedUpsert = `INSERT INTO analysis_reports (key, report_kind, market_date, category_key, generated_at, generator_version, content_sha256, content_json, imported_at)
    WITH existing_cohort AS (
      SELECT key,
        CASE
          WHEN json_valid(content_json) THEN
            CASE
              WHEN json_type(content_json, '$.receiptSha256') = 'text'
                THEN lower(json_extract(content_json, '$.receiptSha256'))
              ELSE NULL
            END
          ELSE NULL
        END AS receipt_sha256
      FROM analysis_reports
      WHERE report_kind = 'daily' AND market_date = ?
    )
    SELECT incoming.key, incoming.report_kind, incoming.market_date, incoming.category_key, incoming.generated_at, incoming.generator_version, incoming.content_sha256, incoming.content_json, incoming.imported_at
    FROM (${incomingRows}) AS incoming
    WHERE EXISTS (SELECT 1 FROM snapshots WHERE market_date = ? AND lower(receipt_sha256) = ?)
      AND (
        (SELECT COUNT(*) FROM existing_cohort) = 0
        OR (
          (SELECT COUNT(*) FROM existing_cohort) = 4
          AND (SELECT COUNT(*) FROM existing_cohort WHERE key IN (${placeholders})) = 4
          AND (
            SELECT COUNT(*) FROM existing_cohort
            WHERE receipt_sha256 IS NOT NULL
              AND length(receipt_sha256) = 64
              AND receipt_sha256 NOT GLOB '*[^0-9a-f]*'
          ) = 4
          AND (SELECT COUNT(DISTINCT receipt_sha256) FROM existing_cohort) = 1
          AND (SELECT MAX(receipt_sha256) FROM existing_cohort) <> ?
        )
      )
    ON CONFLICT(key) DO UPDATE SET report_kind=excluded.report_kind, market_date=excluded.market_date, category_key=excluded.category_key, generated_at=excluded.generated_at, generator_version=excluded.generator_version, content_sha256=excluded.content_sha256, content_json=excluded.content_json, imported_at=excluded.imported_at`;
  const values = reports.flatMap((report) => [report.key, report.reportKind, report.marketDate, report.categoryKey, report.generatedAt, report.generatorVersion, report.contentSha256, JSON.stringify(report), now]);
  values.unshift(marketDate);
  values.push(marketDate, receiptSha256, ...reports.map((report) => report.key), receiptSha256);
  const writeResult = await db.prepare(guardedUpsert).bind(...values).run();
  const changes = Number(writeResult.meta.changes ?? 0);
  if (changes === reports.length) return Response.json({ status: "imported", marketDate, reportKind: "daily", reports: reports.length }, { status: 201 });

  const snapshot = await db.prepare("SELECT receipt_sha256 FROM snapshots WHERE market_date = ?").bind(marketDate).first<{ receipt_sha256: string }>();
  if (!snapshot || snapshot.receipt_sha256.toLowerCase() !== receiptSha256) return Response.json({ error: "snapshot_receipt_mismatch" }, { status: 409 });
  const existingReports: Array<StoredAnalysisReport | null> = [];
  for (const report of reports) existingReports.push(await db.prepare("SELECT content_sha256, content_json FROM analysis_reports WHERE key = ?").bind(report.key).first<StoredAnalysisReport>());
  const duplicate = existingReports.every((existing, index) => {
    if (!existing || existing.content_sha256 !== reports[index].contentSha256) return false;
    try { return String((JSON.parse(existing.content_json) as { receiptSha256?: unknown }).receiptSha256 ?? "").toLowerCase() === receiptSha256; } catch { return false; }
  });
  if (duplicate) return Response.json({ status: "duplicate", marketDate, reportKind: "daily", reports: reports.length });
  return Response.json({ error: "immutable_key_conflict" }, { status: 409 });
}

export async function POST(request: Request) {
  if (!authorizeSyncRequest(request, env.SYNC_SECRET as string | undefined)) return Response.json({ error: "unauthorized" }, { status: 401 });
  let payload: unknown;
  try { payload = await request.json(); } catch { return Response.json({ error: "invalid_json" }, { status: 400 }); }
  if (payload && typeof payload === "object" && "reports" in payload && "categoryKey" in payload) {
    const scoped = validateCategoryReportEnvelope(payload, validateAnalysisReport);
    if (!scoped) return Response.json({ error: "invalid_category_report_bundle" }, { status: 400 });
    const db = getD1();
    await ensureSchema(db);
    return storeCategoryReport(db, "analysis_reports", scoped.report, scoped.receiptSha256);
  }
  if (payload && typeof payload === "object" && Object.prototype.hasOwnProperty.call(payload, "reports")) return storeDailyReportBundle(payload);
  const validated = validateAnalysisReport(payload);
  if (!validated.ok) return Response.json({ error: "invalid_analysis_report" }, { status: 400 });
  const report = validated.report;
  if (report.reportKind === "daily") return Response.json({ error: "daily_analysis_requires_bundle" }, { status: 400 });
  const db = getD1();
  await ensureSchema(db);
  const existing = await db.prepare("SELECT content_sha256 FROM analysis_reports WHERE key = ?").bind(report.key).first<{ content_sha256: string }>();
  if (existing) {
    if (existing.content_sha256 === report.contentSha256) return Response.json({ status: "duplicate", key: report.key });
    return Response.json({ error: "immutable_key_conflict" }, { status: 409 });
  }
  await db.prepare("INSERT INTO analysis_reports (key, report_kind, market_date, category_key, generated_at, generator_version, content_sha256, content_json, imported_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")
    .bind(report.key, report.reportKind, report.marketDate, report.categoryKey, report.generatedAt, report.generatorVersion, report.contentSha256, JSON.stringify(report), new Date().toISOString()).run();
  return Response.json({ status: "imported", key: report.key }, { status: 201 });
}
