import type { Observation } from "./analytics";
import type { CategoryKey } from "./catalog";
import type { ProductMetadata } from "./product-metadata";

type D1Statement = {
  bind(...values: unknown[]): D1Statement;
  all<T>(): Promise<{ results: T[] }>;
};

type D1ReadableDatabase = {
  prepare(sql: string): D1Statement;
};

export type SnapshotRow = { market_date: string; observed_at: string; complete_category_count: number };
export type CategoryDayRow = { market_date: string; category_key: CategoryKey; observation_count: number; complete: number; missing_ranks_json: string };
export type ObservationRow = Observation & { market_date: string; category_key: CategoryKey };
export type ProductMetadataRow = ProductMetadata;
type RawObservationRow = Omit<ObservationRow, "has_discount" | "discounts"> & { has_discount?: unknown; discounts_json?: unknown };
type RawProductMetadataRow = {
  marketplace: ProductMetadata["marketplace"];
  asin: string;
  product_type: ProductMetadata["productType"];
  classification_confidence: ProductMetadata["classificationConfidence"];
  classification_rule_id: string | null;
  classification_rule_version: string;
  classification_evidence_json: unknown;
  raw_brand: string | null;
  normalized_brand: string | null;
  normalized_brand_key: string | null;
  brand_alias_rule_id: string | null;
  brand_source: ProductMetadata["brandSource"];
  first_seen_market_date: string;
  last_seen_market_date: string;
};

function asNullableNumber(value: unknown, valid: (number: number) => boolean): number | null {
  if (value === null) return null;
  if (typeof value === "number") return Number.isFinite(value) && valid(value) ? value : null;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) && valid(parsed) ? parsed : null;
  }
  return null;
}

function asDiscounts(value: unknown) {
  type DiscountRow = { kind: Observation["discounts"][number]["kind"]; amount: string };
  const isDiscountRow = (discount: unknown): discount is DiscountRow => {
    if (!discount || typeof discount !== "object") return false;
    const record = discount as Record<string, unknown>;
    return ["COUPON", "PRICE_DROP", "PRIME_EXCLUSIVE"].includes(String(record.kind))
      && typeof record.amount === "string"
      && record.amount.trim() !== "";
  };
  if (typeof value !== "string") return [];
  try {
    const parsed: unknown = JSON.parse(value);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(isDiscountRow).map((discount) => ({ kind: discount.kind, amount: discount.amount.trim() }));
  } catch {
    return [];
  }
}

function asNullableBoolean(value: unknown) {
  if (value === true || value === 1 || value === "1") return true;
  if (value === false || value === 0 || value === "0") return false;
  return null;
}

function asClassificationEvidence(value: unknown): string[] {
  if (typeof value !== "string") return [];
  try {
    const parsed: unknown = JSON.parse(value);
    return Array.isArray(parsed) && parsed.every((item) => typeof item === "string") ? parsed : [];
  } catch {
    return [];
  }
}

function normalizeObservation(row: RawObservationRow): ObservationRow {
  const discounts = asDiscounts(row.discounts_json);
  const discountState = asNullableBoolean(row.has_discount);
  return {
    ...row,
    price: asNullableNumber(row.price, (value) => value >= 0),
    rating: asNullableNumber(row.rating, (value) => value >= 0 && value <= 5),
    reviews: asNullableNumber(row.reviews, (value) => value >= 0 && Number.isInteger(value)),
    has_discount: discountState === true && discounts.length > 0 ? true : discountState === false && discounts.length === 0 ? false : null,
    discounts,
  };
}

function normalizeProductMetadata(row: RawProductMetadataRow): ProductMetadataRow {
  return {
    marketplace: row.marketplace,
    asin: row.asin,
    productType: row.product_type,
    classificationConfidence: row.classification_confidence,
    classificationRuleId: row.classification_rule_id,
    classificationRuleVersion: row.classification_rule_version,
    classificationEvidence: asClassificationEvidence(row.classification_evidence_json),
    rawBrand: row.raw_brand,
    normalizedBrand: row.normalized_brand,
    normalizedBrandKey: row.normalized_brand_key,
    brandAliasRuleId: row.brand_alias_rule_id,
    brandSource: row.brand_source,
    firstSeenMarketDate: row.first_seen_market_date,
    lastSeenMarketDate: row.last_seen_market_date,
  };
}

export interface DashboardStore {
  listSnapshots(): Promise<SnapshotRow[]>;
  listCategoryDays(): Promise<CategoryDayRow[]>;
  listObservations(): Promise<ObservationRow[]>;
  listCategoryObservations(marketDate: string, categoryKey: CategoryKey): Promise<ObservationRow[]>;
  listProductHistory(asin: string): Promise<ObservationRow[]>;
  listProductMetadata(): Promise<ProductMetadataRow[]>;
  listProductMetadataByAsins(asins: string[]): Promise<ProductMetadataRow[]>;
}

export function createD1DashboardStore(db: D1ReadableDatabase): DashboardStore {
  return {
    async listSnapshots() {
      const result = await db.prepare("SELECT market_date, observed_at, complete_category_count FROM snapshots ORDER BY market_date").all<SnapshotRow>();
      return result.results;
    },
    async listCategoryDays() {
      const result = await db.prepare("SELECT market_date, category_key, observation_count, complete, missing_ranks_json FROM category_days ORDER BY market_date, category_key").all<CategoryDayRow>();
      return result.results;
    },
    async listObservations() {
      const result = await db.prepare("SELECT o.market_date, o.category_key, o.rank, o.asin, o.title, o.url, o.price, o.rating, o.reviews, d.has_discount, d.discounts_json FROM observations AS o LEFT JOIN observation_discounts AS d ON d.market_date = o.market_date AND d.category_key = o.category_key AND d.rank = o.rank ORDER BY o.market_date, o.category_key, o.rank").all<RawObservationRow>();
      return result.results.map(normalizeObservation);
    },
    async listCategoryObservations(marketDate, categoryKey) {
      const result = await db.prepare("SELECT o.market_date, o.category_key, o.rank, o.asin, o.title, o.url, o.price, o.rating, o.reviews, d.has_discount, d.discounts_json FROM observations AS o LEFT JOIN observation_discounts AS d ON d.market_date = o.market_date AND d.category_key = o.category_key AND d.rank = o.rank WHERE o.market_date = ? AND o.category_key = ? ORDER BY o.rank").bind(marketDate, categoryKey).all<RawObservationRow>();
      return result.results.map(normalizeObservation);
    },
    async listProductHistory(asin) {
      const result = await db.prepare("SELECT o.market_date, o.category_key, o.rank, o.asin, o.title, o.url, o.price, o.rating, o.reviews, d.has_discount, d.discounts_json FROM observations AS o LEFT JOIN observation_discounts AS d ON d.market_date = o.market_date AND d.category_key = o.category_key AND d.rank = o.rank WHERE o.asin = ? ORDER BY o.market_date").bind(asin).all<RawObservationRow>();
      return result.results.map(normalizeObservation);
    },
    async listProductMetadata() {
      const result = await db.prepare("SELECT marketplace, asin, product_type, classification_confidence, classification_rule_id, classification_rule_version, classification_evidence_json, raw_brand, normalized_brand, normalized_brand_key, brand_alias_rule_id, brand_source, first_seen_market_date, last_seen_market_date FROM product_metadata ORDER BY marketplace, asin").all<RawProductMetadataRow>();
      return result.results.map(normalizeProductMetadata);
    },
    async listProductMetadataByAsins(asins) {
      if (asins.length === 0) return [];
      const placeholders = asins.map(() => "?").join(", ");
      const result = await db.prepare(`SELECT marketplace, asin, product_type, classification_confidence, classification_rule_id, classification_rule_version, classification_evidence_json, raw_brand, normalized_brand, normalized_brand_key, brand_alias_rule_id, brand_source, first_seen_market_date, last_seen_market_date FROM product_metadata WHERE asin IN (${placeholders}) ORDER BY marketplace, asin`).bind(...asins).all<RawProductMetadataRow>();
      return result.results.map(normalizeProductMetadata);
    },
  };
}
