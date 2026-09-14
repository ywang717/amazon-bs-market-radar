import { isSafeAnalysisReportKey, validateAnalysisReport } from "@/lib/analysis-report-contract";
import { ensureSchema, getD1 } from "@/lib/d1";

export async function GET(_: Request, { params }: { params: Promise<{ key: string[] }> }) {
  const { key: parts } = await params;
  const key = parts.join("/");
  if (!isSafeAnalysisReportKey(key)) return Response.json({ error: "not_found" }, { status: 404 });
  try {
    const db = getD1(); await ensureSchema(db);
    const row = await db.prepare("SELECT content_json FROM analysis_reports WHERE key = ?").bind(key).first<{ content_json: string }>();
    if (!row) return Response.json({ error: "not_found" }, { status: 404 });
    const validated = validateAnalysisReport(JSON.parse(row.content_json));
    if (!validated.ok) return Response.json({ error: "not_found" }, { status: 404 });
    return Response.json(validated.report, { headers: { "cache-control": "public, max-age=300" } });
  } catch { return Response.json({ error: "not_found" }, { status: 404 }); }
}
