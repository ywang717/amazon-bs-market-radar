import { isSafeSellerIntelligenceKey, liveCacheHeader, readSellerIntelligenceReport } from "@/lib/seller-intelligence";

export async function GET(_: Request, { params }: { params: Promise<{ key: string[] }> }) {
  const { key: parts } = await params;
  const key = parts.join("/");
  if (!isSafeSellerIntelligenceKey(key)) return Response.json({ error: "not_found" }, { status: 404 });

  try {
    const report = await readSellerIntelligenceReport(key);
    if (report.status !== "found") return Response.json({ error: "not_found" }, { status: 404 });
    return Response.json(report.report, { headers: liveCacheHeader });
  } catch {
    return Response.json({ error: "not_found" }, { status: 404 });
  }
}
