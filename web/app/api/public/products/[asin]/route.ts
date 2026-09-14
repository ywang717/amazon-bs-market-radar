import { loadLiveProduct } from "@/lib/live-dashboard-data";
import { isValidAsin } from "@/lib/public-validation";

export async function GET(_: Request, { params }: { params: Promise<{ asin: string }> }) {
  const { asin } = await params;
  if (!isValidAsin(asin)) return Response.json({ error: "invalid_asin" }, { status: 400 });
  const result = await loadLiveProduct(asin);
  if (result.status === "not_found") return Response.json({ error: "not_found" }, { status: 404 });
  return Response.json(
    { asin, ...result.product },
    { headers: { "cache-control": `public, max-age=${result.source === "d1" ? 300 : 60}` } },
  );
}
