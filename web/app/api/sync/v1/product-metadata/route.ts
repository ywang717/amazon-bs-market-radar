import { env } from "cloudflare:workers";
import { validateBrandMetadataRefreshRequest } from "@/lib/brand-metadata-refresh-contract";
import { ensureSchema, getD1 } from "@/lib/d1";
import { buildProductMetadataBulkUpsertStatement, isTrustedBrandSource } from "@/lib/product-metadata-upsert";
import { authorizeSyncRequest } from "@/lib/sync-auth";

type ExistingBrand = {
  asin: string;
  normalized_brand_key: string | null;
  brand_source: string;
};

export async function POST(request: Request) {
  if (!authorizeSyncRequest(request, env.SYNC_SECRET as string | undefined)) return Response.json({ error: "unauthorized" }, { status: 401 });
  let payload: unknown;
  try { payload = await request.json(); } catch { return Response.json({ error: "invalid_product_metadata_refresh" }, { status: 400 }); }
  const validated = await validateBrandMetadataRefreshRequest(payload);
  if (!validated.ok) return Response.json({ error: "invalid_product_metadata_refresh" }, { status: 400 });

  const db = getD1();
  await ensureSchema(db);
  const asins = validated.productMetadata.map((metadata) => metadata.asin);
  const existing = await db.prepare("SELECT asin, normalized_brand_key, brand_source FROM product_metadata WHERE marketplace = ? AND asin IN (SELECT value FROM json_each(?))").bind("AMAZON_US", JSON.stringify(asins)).all<ExistingBrand>();
  const existingByAsin = new Map((existing.results ?? []).map((row) => [row.asin, row]));
  const conflict = validated.productMetadata.some((metadata) => {
    const stored = existingByAsin.get(metadata.asin);
    return isTrustedBrandSource(metadata.brandSource)
      && stored !== undefined
      && isTrustedBrandSource(stored.brand_source)
      && (stored.normalized_brand_key === null
        || stored.normalized_brand_key.trim() === ""
        || stored.normalized_brand_key !== metadata.normalizedBrandKey);
  });
  if (conflict) return Response.json({ error: "brand_metadata_conflict" }, { status: 409 });

  const writeResults = await db.batch([buildProductMetadataBulkUpsertStatement(db, validated.productMetadata)]);
  const changedRows = Number(writeResults[0]?.meta?.changes ?? 0);
  if (validated.productMetadata.length > 0 && changedRows !== validated.productMetadata.length) {
    return Response.json({ error: "brand_metadata_conflict" }, { status: 409 });
  }
  return Response.json({ status: "imported", productMetadata: validated.productMetadata.length }, { status: 201 });
}
