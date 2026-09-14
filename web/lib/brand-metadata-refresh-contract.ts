import { type ProductMetadata } from "./product-metadata.ts";
import { validateProductMetadataRow } from "./sync-contract.ts";

const asinPattern = /^[A-Z0-9]{10}$/;
const sha256Pattern = /^[a-f0-9]{64}$/i;
const verificationStatuses = ["VERIFIED", "MISSING", "CONFLICT", "IDENTITY_MISMATCH", "VERIFICATION_BLOCKED"] as const;
const verifiedEvidenceSources = new Set(["PRODUCT_OVERVIEW_BRAND_FIELD", "PRODUCT_DETAILS_BRAND_FIELD", "DETAIL_BULLET_BRAND_FIELD"]);

type VerificationStatus = typeof verificationStatuses[number];

export interface BrandEnrichmentReceipt {
  schema_version: "amazon-brand-enrichment-receipt-v1";
  generated_at: string;
  marketplace: "AMAZON_US";
  requested_asin_set_sha256: string;
  artifact_sha256: string;
  record_count: number;
  status_counts: Record<VerificationStatus, number>;
}

export interface BrandMetadataRefreshRequest {
  schemaVersion: "amazon-brand-metadata-refresh-v1";
  marketplace: "AMAZON_US";
  artifactJson: string;
  artifactSha256: string;
  receipt: BrandEnrichmentReceipt;
  productMetadata: ProductMetadata[];
}

type ArtifactProduct = {
  asin: string;
  detail_url: string;
  verification_status: VerificationStatus;
  raw_brand: string | null;
  brand_source: "verified_metadata" | "unknown";
  evidence_source: string | null;
};

type BrandEnrichmentArtifact = {
  schema_version: "amazon-brand-enrichment-v1";
  marketplace: "AMAZON_US";
  generated_at: string;
  products: ArtifactProduct[];
};

function isValidDateTime(value: unknown) {
  return typeof value === "string" && value.trim() !== "" && !Number.isNaN(Date.parse(value));
}

function hasOwn(value: object, key: string) {
  return Object.prototype.hasOwnProperty.call(value, key);
}

async function hashUtf8(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function asinSetHash(asins: string[]) {
  return hashUtf8([...new Set(asins)].sort().join("\n"));
}

function validateArtifactProduct(value: unknown, errors: string[], previousAsin: string | null): ArtifactProduct | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    errors.push("artifact 产品无效");
    return null;
  }
  const product = value as Record<string, unknown>;
  for (const field of ["asin", "detail_url", "verification_status", "raw_brand", "brand_source", "evidence_source"]) {
    if (!hasOwn(product, field)) errors.push(`artifact 产品缺少 ${field}`);
  }
  const asin = product.asin;
  if (typeof asin !== "string" || !asinPattern.test(asin)) errors.push("artifact ASIN 无效");
  if (typeof asin === "string" && asinPattern.test(asin) && previousAsin !== null && previousAsin >= asin) errors.push("artifact ASIN 必须唯一并按序排列");
  if (typeof asin === "string" && asinPattern.test(asin) && product.detail_url !== `https://www.amazon.com/dp/${asin}`) errors.push("artifact 产品 URL 无效");
  const status = product.verification_status;
  if (typeof status !== "string" || !verificationStatuses.includes(status as VerificationStatus)) errors.push("artifact 验证状态无效");
  const rawBrand = product.raw_brand;
  const brandSource = product.brand_source;
  const evidenceSource = product.evidence_source;
  if (status === "VERIFIED") {
    if (typeof rawBrand !== "string" || rawBrand.trim() === "" || brandSource !== "verified_metadata" || typeof evidenceSource !== "string" || !verifiedEvidenceSources.has(evidenceSource)) errors.push("artifact VERIFIED 品牌来源无效");
  } else if (rawBrand !== null || brandSource !== "unknown" || evidenceSource !== null) {
    errors.push("artifact 未验证产品不得携带品牌值");
  }
  return product as ArtifactProduct;
}

export async function validateBrandMetadataRefreshRequest(input: unknown) {
  const request = (input ?? {}) as Record<string, unknown>;
  const errors: string[] = [];
  if (request.schemaVersion !== "amazon-brand-metadata-refresh-v1") errors.push("不支持的元数据刷新版本");
  if (request.marketplace !== "AMAZON_US") errors.push("刷新 marketplace 无效");
  if (typeof request.artifactJson !== "string") errors.push("artifactJson 必须是字符串");
  if (!sha256Pattern.test(String(request.artifactSha256 ?? ""))) errors.push("artifactSha256 无效");

  let artifact: BrandEnrichmentArtifact | null = null;
  if (typeof request.artifactJson === "string") {
    const actualHash = await hashUtf8(request.artifactJson);
    if (actualHash !== request.artifactSha256) errors.push("artifactSha256 必须匹配 artifactJson 原始 UTF-8 字节");
    try {
      const parsed = JSON.parse(request.artifactJson) as unknown;
      if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
        errors.push("artifact 必须是对象");
      } else {
        const value = parsed as Record<string, unknown>;
        if (value.schema_version !== "amazon-brand-enrichment-v1") errors.push("artifact schema 无效");
        if (value.marketplace !== "AMAZON_US") errors.push("artifact marketplace 无效");
        if (!isValidDateTime(value.generated_at)) errors.push("artifact generated_at 无效");
        if (!Array.isArray(value.products)) {
          errors.push("artifact products 无效");
        } else {
          const products: ArtifactProduct[] = [];
          let previousAsin: string | null = null;
          for (const product of value.products) {
            const errorCount = errors.length;
            const validated = validateArtifactProduct(product, errors, previousAsin);
            if (validated !== null && errors.length === errorCount) {
              products.push(validated);
              previousAsin = validated.asin;
            }
          }
          if (products.length === value.products.length) artifact = { ...value, products } as BrandEnrichmentArtifact;
        }
      }
    } catch {
      errors.push("artifactJson 不是有效 JSON");
    }
  }

  const receipt = request.receipt as Record<string, unknown> | null;
  if (receipt === null || typeof receipt !== "object" || Array.isArray(receipt)) {
    errors.push("receipt 无效");
  } else {
    if (receipt.schema_version !== "amazon-brand-enrichment-receipt-v1") errors.push("receipt schema 无效");
    if (receipt.marketplace !== "AMAZON_US") errors.push("receipt marketplace 无效");
    if (!isValidDateTime(receipt.generated_at)) errors.push("receipt generated_at 无效");
    if (!sha256Pattern.test(String(receipt.artifact_sha256 ?? ""))) errors.push("receipt artifact_sha256 无效");
    if (!sha256Pattern.test(String(receipt.requested_asin_set_sha256 ?? ""))) errors.push("receipt requested_asin_set_sha256 无效");
    if (!Number.isInteger(receipt.record_count) || Number(receipt.record_count) < 0) errors.push("receipt record_count 无效");
    if (receipt.artifact_sha256 !== request.artifactSha256) errors.push("receipt artifact hash 与请求不一致");
    const counts = receipt.status_counts;
    if (counts === null || typeof counts !== "object" || Array.isArray(counts)) {
      errors.push("receipt status_counts 无效");
    } else {
      for (const status of verificationStatuses) {
        if (!hasOwn(counts, status) || !Number.isInteger((counts as Record<string, unknown>)[status]) || Number((counts as Record<string, unknown>)[status]) < 0) errors.push(`receipt ${status} 计数无效`);
      }
    }
  }

  const artifactProducts = artifact?.products ?? [];
  if (artifact !== null && receipt !== null && typeof receipt === "object" && !Array.isArray(receipt)) {
    if (receipt.record_count !== artifactProducts.length) errors.push("receipt record_count 与 artifact 不一致");
    const artifactAsins = artifactProducts.map((product) => product.asin);
    if (receipt.requested_asin_set_sha256 !== await asinSetHash(artifactAsins)) errors.push("receipt ASIN 集合哈希与 artifact 不一致");
    const counts = receipt.status_counts as Record<string, unknown>;
    for (const status of verificationStatuses) {
      if (counts?.[status] !== artifactProducts.filter((product) => product.verification_status === status).length) errors.push(`receipt ${status} 计数与 artifact 不一致`);
    }
  }

  const productMetadata: ProductMetadata[] = [];
  if (!Array.isArray(request.productMetadata)) {
    errors.push("productMetadata 必须是数组");
  } else {
    for (const row of request.productMetadata) {
      try {
        productMetadata.push(validateProductMetadataRow(row));
      } catch (error) {
        errors.push(error instanceof Error ? error.message : "productMetadata 无效");
      }
    }
    const metadataAsins = productMetadata.map((row) => row.asin);
    if (new Set(metadataAsins).size !== metadataAsins.length) errors.push("productMetadata ASIN 必须唯一");
    const artifactByAsin = new Map(artifactProducts.map((product) => [product.asin, product]));
    if (metadataAsins.length !== artifactByAsin.size || metadataAsins.some((asin) => !artifactByAsin.has(asin))) errors.push("productMetadata ASIN 集合必须与 artifact 一致");
    for (const row of productMetadata) {
      const product = artifactByAsin.get(row.asin);
      if (product?.verification_status === "VERIFIED") {
        if (row.rawBrand !== product.raw_brand || row.brandSource !== "verified_metadata") errors.push(`VERIFIED ${row.asin} 品牌必须匹配 artifact`);
      } else if (product !== undefined && [row.rawBrand, row.normalizedBrand, row.normalizedBrandKey, row.brandAliasRuleId].some((value) => value !== null)) {
        errors.push(`未验证 ${row.asin} 不得携带品牌值`);
      }
    }
  }
  return { ok: errors.length === 0, errors, artifact, productMetadata };
}
