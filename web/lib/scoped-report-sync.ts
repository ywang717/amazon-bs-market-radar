type CategoryReport = {
  key: string; reportKind: string; marketDate: string; categoryKey: string | null;
  generatedAt: string; generatorVersion: string; contentSha256: string; profile?: string;
};

export function validateCategoryReportEnvelope<T extends CategoryReport>(payload: unknown, validate: (input: unknown) => { ok: true; report: T } | { ok: false; errors: string[] }) {
  const input = payload as { categoryKey?: unknown; receiptSha256?: unknown; reports?: unknown };
  if (typeof input?.categoryKey !== "string" || typeof input.receiptSha256 !== "string" || !/^[a-f0-9]{64}$/i.test(input.receiptSha256)
    || !Array.isArray(input.reports) || input.reports.length !== 1) return null;
  const result = validate(input.reports[0]);
  if (!result.ok || result.report.reportKind !== "daily" || result.report.categoryKey !== input.categoryKey) return null;
  return { report: result.report, receiptSha256: input.receiptSha256.toLowerCase() };
}

export async function storeCategoryReport(db: D1Database, table: "analysis_reports" | "seller_intelligence_reports", report: CategoryReport, receiptSha256: string) {
  if (!report.categoryKey || report.reportKind !== "daily" || !/^[a-f0-9]{64}$/.test(receiptSha256)) {
    return Response.json({ error: "invalid_category_report" }, { status: 400 });
  }
  const authorization = `EXISTS (SELECT 1 FROM category_capture_receipts WHERE market_date = ? AND category_key = ? AND lower(receipt_sha256) = ?)
    OR (EXISTS (SELECT 1 FROM snapshots WHERE market_date = ? AND lower(receipt_sha256) = ?)
      AND NOT EXISTS (SELECT 1 FROM category_capture_receipts WHERE market_date = ? AND category_key = ?))`;
  const authorizationValues = [report.marketDate, report.categoryKey, receiptSha256, report.marketDate, receiptSha256, report.marketDate, report.categoryKey];
  const columns = ["key", "report_kind", "market_date", "category_key", "generated_at", "generator_version", "content_sha256", "content_json", "imported_at"];
  const values = [report.key, report.reportKind, report.marketDate, report.categoryKey, report.generatedAt, report.generatorVersion, report.contentSha256, JSON.stringify({ ...report, receiptSha256 }), new Date().toISOString()];
  if (table === "seller_intelligence_reports") {
    columns.push("profile");
    values.push(report.profile ?? "");
  }
  // Receipt authorization and immutable-within-receipt update are a single SQL operation.
  const result = await db.prepare(`INSERT INTO ${table} (${columns.join(",")})
    SELECT ${columns.map(() => "?").join(",")} WHERE (${authorization})
    ON CONFLICT(key) DO UPDATE SET ${columns.slice(1).map((column) => `${column}=excluded.${column}`).join(",")}
    WHERE COALESCE(CASE WHEN json_valid(${table}.content_json) THEN lower(json_extract(${table}.content_json,'$.receiptSha256')) END,'') <> ?`)
    .bind(...values, ...authorizationValues, receiptSha256).run();
  if (Number(result.meta.changes) === 1) return Response.json({ status: "imported", marketDate: report.marketDate, categoryKey: report.categoryKey, reports: 1 }, { status: 201 });
  const authorized = await db.prepare(`SELECT (${authorization}) AS allowed`).bind(...authorizationValues).first<{ allowed: number }>();
  if (!authorized?.allowed) return Response.json({ error: "category_receipt_mismatch" }, { status: 409 });
  const existing = await db.prepare(`SELECT content_sha256, content_json FROM ${table} WHERE key = ?`).bind(report.key).first<{ content_sha256: string; content_json: string }>();
  if (existing?.content_sha256 === report.contentSha256) {
    try {
      if (JSON.parse(existing.content_json).receiptSha256 === receiptSha256) return Response.json({ status: "duplicate", reports: 1 });
    } catch { /* Invalid legacy content cannot establish duplicate identity. */ }
  }
  return Response.json({ error: "immutable_key_conflict" }, { status: 409 });
}
