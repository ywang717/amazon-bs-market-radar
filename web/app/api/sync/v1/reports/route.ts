import { env } from "cloudflare:workers";
import { authorizeSyncRequest } from "@/lib/sync-auth";
import { ensureSchema, getD1, getReportsBucket } from "@/lib/d1";
import { categories } from "@/lib/catalog";
import { productionMarketContextResolver } from "@/lib/market-context";

const keyPattern = /^[a-z0-9][a-z0-9/_-]*\.pdf$/i;
export async function POST(request: Request) {
  if (!authorizeSyncRequest(request, env.SYNC_SECRET as string | undefined)) return Response.json({ error: "unauthorized" }, { status: 401 });
  const key = request.headers.get("x-report-key") ?? ""; const marketDate = request.headers.get("x-market-date") ?? ""; const kind = request.headers.get("x-report-kind") ?? ""; const categoryKey = request.headers.get("x-category-key"); const segmentKey = request.headers.get("x-segment-key"); const title = request.headers.get("x-report-title") ?? "Amazon BS 报告";
  const segmentValid = !segmentKey || (categoryKey && productionMarketContextResolver.isSegmentSupported(categoryKey, segmentKey));
  if (!keyPattern.test(key) || key.includes("..") || !/^\d{4}-\d{2}-\d{2}$/.test(marketDate) || !["daily", "weekly"].includes(kind) || (categoryKey && !categories.some(({ key }) => key === categoryKey)) || !segmentValid || request.headers.get("content-type") !== "application/pdf") return Response.json({ error: "invalid_report_metadata" }, { status: 400 });
  const body = await request.arrayBuffer(); if (body.byteLength < 5 || new TextDecoder().decode(body.slice(0, 5)) !== "%PDF-") return Response.json({ error: "invalid_pdf" }, { status: 400 });
  const bucket = getReportsBucket(); await bucket.put(key, body, { httpMetadata: { contentType: "application/pdf" }, customMetadata: { marketDate, kind, categoryKey: categoryKey ?? "", segmentKey: segmentKey ?? "" } });
  const db = getD1(); await ensureSchema(db); await db.prepare("INSERT OR REPLACE INTO reports (key, market_date, category_key, segment_key, kind, title, byte_count, uploaded_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)").bind(key, marketDate, categoryKey, segmentKey, kind, title.slice(0, 160), body.byteLength, new Date().toISOString()).run();
  return Response.json({ status: "uploaded", key, byteCount: body.byteLength }, { status: 201 });
}
