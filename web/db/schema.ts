import { sql } from "drizzle-orm";
import { check, index, integer, primaryKey, real, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const snapshots = sqliteTable("snapshots", {
  marketDate: text("market_date").primaryKey(),
  observedAt: text("observed_at").notNull(),
  receiptSha256: text("receipt_sha256").notNull().unique(),
  publicStatus: text("public_status").notNull(),
  completeCategoryCount: integer("complete_category_count").notNull(),
  importedAt: text("imported_at").notNull(),
});

export const categoryCaptureReceipts = sqliteTable("category_capture_receipts", {
  marketDate: text("market_date").notNull(),
  categoryKey: text("category_key").notNull(),
  receiptSha256: text("receipt_sha256").notNull(),
  observedAt: text("observed_at").notNull(),
}, (table) => [primaryKey({ columns: [table.marketDate, table.categoryKey] })]);

export const marketSyncGuard = sqliteTable("market_sync_guard", {
  guardKey: text("guard_key").primaryKey(),
  conflict: integer("conflict").notNull(),
}, (table) => [check("market_sync_guard_check", sql`${table.conflict} = 0`)]);

export const categoryDays = sqliteTable("category_days", {
  marketDate: text("market_date").notNull(),
  categoryKey: text("category_key").notNull(),
  sourceUrl: text("source_url").notNull(),
  observationCount: integer("observation_count").notNull(),
  complete: integer("complete", { mode: "boolean" }).notNull(),
  missingRanksJson: text("missing_ranks_json").notNull(),
}, (table) => [primaryKey({ columns: [table.marketDate, table.categoryKey] })]);

export const observations = sqliteTable("observations", {
  marketDate: text("market_date").notNull(),
  categoryKey: text("category_key").notNull(),
  rank: integer("rank").notNull(),
  asin: text("asin").notNull(),
  title: text("title").notNull(),
  url: text("url").notNull(),
  price: real("price"),
  rating: real("rating"),
  reviews: integer("reviews"),
}, (table) => [primaryKey({ columns: [table.marketDate, table.categoryKey, table.rank] })]);

export const observationDiscounts = sqliteTable("observation_discounts", {
  marketDate: text("market_date").notNull(),
  categoryKey: text("category_key").notNull(),
  rank: integer("rank").notNull(),
  hasDiscount: integer("has_discount", { mode: "boolean" }),
  discountsJson: text("discounts_json").notNull(),
}, (table) => [primaryKey({ columns: [table.marketDate, table.categoryKey, table.rank] })]);

export const reports = sqliteTable("reports", {
  key: text("key").primaryKey(),
  marketDate: text("market_date").notNull(),
  categoryKey: text("category_key"),
  kind: text("kind").notNull(),
  title: text("title").notNull(),
  byteCount: integer("byte_count").notNull(),
  uploadedAt: text("uploaded_at").notNull(),
});

export const analysisReports = sqliteTable("analysis_reports", {
  key: text("key").primaryKey(),
  reportKind: text("report_kind").notNull(),
  marketDate: text("market_date").notNull(),
  categoryKey: text("category_key"),
  generatedAt: text("generated_at").notNull(),
  generatorVersion: text("generator_version").notNull(),
  contentSha256: text("content_sha256").notNull(),
  contentJson: text("content_json").notNull(),
  importedAt: text("imported_at").notNull(),
}, (table) => [index("idx_analysis_reports_market_date").on(table.marketDate, table.reportKind, table.categoryKey)]);

export const sellerIntelligenceReports = sqliteTable("seller_intelligence_reports", {
  key: text("key").primaryKey(),
  reportKind: text("report_kind").notNull(),
  profile: text("profile").notNull(),
  marketDate: text("market_date").notNull(),
  categoryKey: text("category_key"),
  generatedAt: text("generated_at").notNull(),
  generatorVersion: text("generator_version").notNull(),
  contentSha256: text("content_sha256").notNull(),
  contentJson: text("content_json").notNull(),
  importedAt: text("imported_at").notNull(),
}, (table) => [index("idx_seller_intelligence_reports_market_date").on(table.marketDate, table.reportKind, table.profile, table.categoryKey)]);

export const productMetadata = sqliteTable("product_metadata", {
  marketplace: text("marketplace").notNull(),
  asin: text("asin").notNull(),
  productType: text("product_type").notNull(),
  classificationConfidence: text("classification_confidence").notNull(),
  classificationRuleId: text("classification_rule_id"),
  classificationRuleVersion: text("classification_rule_version").notNull(),
  classificationEvidenceJson: text("classification_evidence_json").notNull(),
  rawBrand: text("raw_brand"),
  normalizedBrand: text("normalized_brand"),
  normalizedBrandKey: text("normalized_brand_key"),
  brandAliasRuleId: text("brand_alias_rule_id"),
  brandSource: text("brand_source").notNull(),
  firstSeenMarketDate: text("first_seen_market_date").notNull(),
  lastSeenMarketDate: text("last_seen_market_date").notNull(),
}, (table) => [
  primaryKey({ columns: [table.marketplace, table.asin] }),
  index("idx_product_metadata_type").on(table.productType),
  index("idx_product_metadata_brand").on(table.normalizedBrandKey),
]);

export const productMetadataBrandConflictGuard = sqliteTable("product_metadata_brand_conflict_guard", {
  guardKey: text("guard_key").primaryKey(),
  conflict: integer("conflict").notNull(),
}, (table) => [
  check("product_metadata_brand_conflict_guard_check", sql`${table.conflict} = 0`),
]);
