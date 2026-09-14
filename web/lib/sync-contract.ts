import { type Discount, type Observation, validateCategory } from "./analytics.ts";
import { normalizeTrustedBrand } from "./brand-normalization.ts";
import { type ProductMetadata } from "./product-metadata.ts";
import { parseCategoryRegistry, productionCategoryRegistry, type RuntimeCategoryRegistry } from "./category-registry.ts";

const allowedProductTypes = new Set(["electric_pressure_washer", "gas_pressure_washer", "cordless_pressure_washer", "surface_cleaner", "pressure_washer_gun", "hose", "nozzle", "foam_cannon", "adapter_connector", "extension_wand", "sewer_jetter", "chemical_cleaner", "pump_protector", "other_accessory", "unknown"]);
const allowedClassificationConfidences = new Set(["high", "medium", "low"]);
const allowedBrandSources = new Set(["verified_metadata", "manual_review", "unknown"]);
const sha256 = /^[a-f0-9]{64}$/i;
const asinPattern = /^[A-Z0-9]{10}$/;
const reportKey = /^[a-z0-9][a-z0-9/_-]*\.pdf$/i;
const marketDatePattern = /^\d{4}-\d{2}-\d{2}$/;

function isAmazonUrl(value: unknown) {
  try {
    const url = new URL(String(value));
    return url.protocol === "https:" && (url.hostname === "amazon.com" || url.hostname.endsWith(".amazon.com"));
  } catch {
    return false;
  }
}

function hasValidOptionalMetrics(observation: Observation) {
  const { price, rating, reviews, has_discount, discounts } = observation;
  return (price === null || typeof price === "number" && Number.isFinite(price) && price >= 0)
    && (rating === null || typeof rating === "number" && Number.isFinite(rating) && rating >= 0 && rating <= 5)
    && (reviews === null || typeof reviews === "number" && Number.isFinite(reviews) && reviews >= 0 && Number.isInteger(reviews))
    && (has_discount === true || has_discount === false || has_discount === null)
    && Array.isArray(discounts)
    && discounts.every((discount: Discount) => ["COUPON", "PRICE_DROP", "PRIME_EXCLUSIVE"].includes(discount.kind) && typeof discount.amount === "string" && discount.amount.trim() !== "")
    && (has_discount === true ? discounts.length > 0 : discounts.length === 0);
}

function isValidMarketDate(value: unknown) {
  const text = String(value ?? "");
  if (!marketDatePattern.test(text)) return false;
  const date = new Date(`${text}T00:00:00Z`);
  return !Number.isNaN(date.valueOf()) && date.toISOString().slice(0, 10) === text;
}

function isValidObservedAt(value: unknown) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) return false;
  return isValidMarketDate(value.slice(0, 10)) && !Number.isNaN(Date.parse(value));
}

function isNullableNonEmptyString(value: unknown) {
  return value === null || typeof value === "string" && value.trim() !== "";
}

export function validateProductMetadataRow(value: unknown): ProductMetadata {
  const errors: string[] = [];
  const raw = value;
  const metadata = (raw ?? {}) as Record<string, unknown>;
  if (metadata.marketplace !== "AMAZON_US") errors.push("元数据 marketplace 无效");
  if (typeof metadata.asin !== "string" || !asinPattern.test(metadata.asin)) errors.push("元数据 ASIN 无效");
  if (typeof metadata.productType !== "string" || !allowedProductTypes.has(metadata.productType)) errors.push("产品类型无效");
  if (typeof metadata.classificationConfidence !== "string" || !allowedClassificationConfidences.has(metadata.classificationConfidence)) errors.push("分类置信度无效");
  if (metadata.productType === "unknown" && metadata.classificationConfidence !== "low") errors.push("unknown 产品类型只允许 low 置信度");
  if (!isNullableNonEmptyString(metadata.classificationRuleId)) errors.push("分类规则 ID 无效");
  if (metadata.productType === "unknown" && metadata.classificationRuleId !== null) errors.push("unknown 产品类型不能有分类规则 ID");
  if (typeof metadata.productType === "string" && allowedProductTypes.has(metadata.productType) && metadata.productType !== "unknown") {
    if (metadata.classificationConfidence !== "medium" && metadata.classificationConfidence !== "high") errors.push("已分类产品只允许 medium 或 high 置信度");
    if (typeof metadata.classificationRuleId !== "string" || metadata.classificationRuleId.trim() === "") errors.push("已分类产品必须包含分类规则 ID");
  }
  if (typeof metadata.classificationRuleVersion !== "string" || metadata.classificationRuleVersion.trim() === "") errors.push("分类规则版本无效");
  if (!Array.isArray(metadata.classificationEvidence) || metadata.classificationEvidence.length === 0 || metadata.classificationEvidence.some((value) => typeof value !== "string" || value.trim() === "")) errors.push("分类证据无效");

  const brandFields = [metadata.rawBrand, metadata.normalizedBrand, metadata.normalizedBrandKey, metadata.brandAliasRuleId];
  if (brandFields.some((value) => !isNullableNonEmptyString(value))) errors.push("品牌字段无效");
  if (typeof metadata.brandSource !== "string" || !allowedBrandSources.has(metadata.brandSource)) errors.push("品牌来源无效");
  if (metadata.brandSource === "unknown" && brandFields.some((value) => value !== null)) errors.push("unknown 品牌的所有品牌字段必须为 null");
  if ((metadata.brandSource === "verified_metadata" || metadata.brandSource === "manual_review")
    && [metadata.rawBrand, metadata.normalizedBrand, metadata.normalizedBrandKey].some((value) => typeof value !== "string" || value.trim() === "")) errors.push("已验证品牌必须包含原始与归一化字段");
  if ((metadata.brandSource === "verified_metadata" || metadata.brandSource === "manual_review")
    && typeof metadata.rawBrand === "string"
    && typeof metadata.normalizedBrand === "string"
    && typeof metadata.normalizedBrandKey === "string") {
    const expected = normalizeTrustedBrand(metadata.rawBrand);
    if (metadata.rawBrand !== expected.rawBrand
      || metadata.normalizedBrand !== expected.normalizedBrand
      || metadata.normalizedBrandKey !== expected.normalizedBrandKey
      || metadata.brandAliasRuleId !== expected.brandAliasRuleId) errors.push("品牌归一化必须匹配权威别名规则");
  }
  if (!isValidMarketDate(metadata.firstSeenMarketDate) || !isValidMarketDate(metadata.lastSeenMarketDate)) errors.push("元数据市场日期无效");
  if (isValidMarketDate(metadata.firstSeenMarketDate) && isValidMarketDate(metadata.lastSeenMarketDate)
    && String(metadata.firstSeenMarketDate) > String(metadata.lastSeenMarketDate)) errors.push("首次出现日期不能晚于最后出现日期");
  if (errors.length > 0) throw new Error(errors.join("; "));
  return metadata as ProductMetadata;
}

export function validateSyncBundle(input: unknown, registry: RuntimeCategoryRegistry = productionCategoryRegistry) {
  const allowedCategories = new Set(parseCategoryRegistry(registry).categories
    .filter(({ enabled }) => enabled).map(({ categoryKey }) => categoryKey));
  const bundle = (input ?? {}) as Record<string, unknown>;
  const errors: string[] = [];
  const isV1 = bundle.schemaVersion === "amazon-bs-dashboard-bundle-v1";
  const isV2 = bundle.schemaVersion === "amazon-bs-dashboard-bundle-v2";
  if (!isV1 && !isV2) errors.push("不支持的同步版本");
  if (!isValidMarketDate(bundle.marketDate)) errors.push("市场日期无效");
  if (isV2 && !isValidObservedAt(bundle.observedAt)) errors.push("观测时间无效");
  if (!sha256.test(String(bundle.receiptSha256 ?? ""))) errors.push("回执哈希无效");
  const categories = Array.isArray(bundle.categories) ? bundle.categories : [];
  if (categories.length === 0) errors.push("至少需要一个榜单");
  const categoryKeys = new Set<string>();
  const normalized = categories.map((raw) => {
    const category = raw as Record<string, unknown>;
    const key = String(category.key ?? "");
    if (categoryKeys.has(key)) errors.push("榜单键必须唯一");
    categoryKeys.add(key);
    const observations = Array.isArray(category.observations)
      ? category.observations.map((raw) => {
        const observation = raw as Record<string, unknown>;
        return {
          ...observation,
          has_discount: observation.has_discount === undefined ? null : observation.has_discount,
          discounts: observation.discounts === undefined ? [] : observation.discounts,
        } as Observation;
      })
      : [];
    if (!allowedCategories.has(key)) errors.push(`榜单键无效：${key}`);
    if (!isAmazonUrl(category.sourceUrl)) errors.push(`榜单来源必须是 Amazon HTTPS URL：${key}`);
    for (const observation of observations) {
      if (!isAmazonUrl(observation.url)) errors.push(`产品 URL 必须是 Amazon HTTPS URL：${observation.asin ?? "unknown"}`);
      if (!hasValidOptionalMetrics(observation)) errors.push("Invalid optional observation metrics");
    }
    return { ...category, key, sourceUrl: String(category.sourceUrl ?? ""), observations, quality: validateCategory(observations) };
  });
  const reports = Array.isArray(bundle.reports) ? bundle.reports : [];
  for (const raw of reports) {
    const report = raw as Record<string, unknown>;
    if (!reportKey.test(String(report.key ?? "")) || String(report.key).includes("..")) errors.push("报告键无效");
    if (report.contentType !== "application/pdf") errors.push("报告必须是 PDF");
  }
  let productMetadata: ProductMetadata[] = [];
  if (isV2) {
    if (!Array.isArray(bundle.productMetadata)) {
      errors.push("v2 bundle 必须包含 productMetadata");
    } else {
      productMetadata = bundle.productMetadata.map((raw) => {
        try {
          return validateProductMetadataRow(raw);
        } catch (error) {
          errors.push(error instanceof Error ? error.message : "元数据无效");
          return (raw ?? {}) as ProductMetadata;
        }
      });
      const metadataKeys = new Set<string>();
      for (const metadata of productMetadata) {
        const key = `${String(metadata.marketplace)}\u0000${String(metadata.asin)}`;
        if (metadataKeys.has(key)) errors.push("productMetadata marketplace + ASIN 必须唯一");
        metadataKeys.add(key);
      }
      const observationAsins = new Set(normalized.flatMap((category) => category.observations.map((observation) => String(observation.asin))));
      const metadataAsins = new Set(productMetadata.map((metadata) => String(metadata.asin)));
      if (observationAsins.size !== metadataAsins.size || [...observationAsins].some((asin) => !metadataAsins.has(asin))) errors.push("productMetadata ASIN 集合必须与 observations 一致");
    }
  }
  return { ok: errors.length === 0, errors, categories: normalized, reports, productMetadata };
}

export type ValidatedSyncBundle = ReturnType<typeof validateSyncBundle> & {
  ok: true;
};

export function sanitizePublicStatus(input: { current: boolean; complete: boolean; internalError?: string }) {
  if (!input.current) return { label: "数据延迟", tone: "danger" };
  if (!input.complete) return { label: "数据不完整", tone: "warning" };
  return { label: "已更新", tone: "good" };
}
