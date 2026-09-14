import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { buildProductMetadataBulkUpsertStatement, buildProductMetadataUpsertStatement, isProductMetadataBrandConflictError } from "../lib/product-metadata-upsert.ts";

function metadata(overrides = {}) {
  return {
    marketplace: "AMAZON_US",
    asin: "B000000001",
    productType: "unknown",
    classificationConfidence: "low",
    classificationRuleId: null,
    classificationRuleVersion: "product-rules-v1",
    classificationEvidence: ["NO_SAFE_RULE_MATCH"],
    rawBrand: null,
    normalizedBrand: null,
    normalizedBrandKey: null,
    brandAliasRuleId: null,
    brandSource: "unknown",
    firstSeenMarketDate: "2026-08-01",
    lastSeenMarketDate: "2026-08-01",
    ...overrides,
  };
}

function database() {
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec(`CREATE TABLE product_metadata (
    marketplace TEXT NOT NULL, asin TEXT NOT NULL, product_type TEXT NOT NULL,
    classification_confidence TEXT NOT NULL, classification_rule_id TEXT,
    classification_rule_version TEXT NOT NULL, classification_evidence_json TEXT NOT NULL,
    raw_brand TEXT, normalized_brand TEXT, normalized_brand_key TEXT,
    brand_alias_rule_id TEXT, brand_source TEXT NOT NULL,
    first_seen_market_date TEXT NOT NULL, last_seen_market_date TEXT NOT NULL,
    PRIMARY KEY (marketplace, asin)
  )`);
  return sqlite;
}

function d1(sqlite) {
  return {
    prepare(sql) {
      let values = [];
      return {
        sql,
        get values() { return values; },
        bind(...bound) { values = bound; return this; },
        run() { return sqlite.prepare(sql).run(...values); },
      };
    },
  };
}

function apply(sqlite, row) {
  const statement = buildProductMetadataUpsertStatement(d1(sqlite), row);
  statement.run();
  return statement;
}

function applyBulk(sqlite, rows) {
  const statement = buildProductMetadataBulkUpsertStatement(d1(sqlite), rows);
  statement.run();
  return statement;
}

function metadataRows(count, overrides = {}) {
  return Array.from({ length: count }, (_, index) => metadata({ asin: `B${String(index + 1).padStart(9, "0")}`, ...overrides }));
}

test("inserts a complete metadata row for a previously unseen ASIN", () => {
  const sqlite = database();
  apply(sqlite, metadata({
    productType: "surface_cleaner", classificationConfidence: "high", classificationRuleId: "surface-cleaner",
    classificationEvidence: ["TITLE_RULE:surface-cleaner"], rawBrand: "Westinghouse", normalizedBrand: "Westinghouse",
    normalizedBrandKey: "westinghouse", brandAliasRuleId: "brand-westinghouse", brandSource: "verified_metadata",
  }));
  const stored = sqlite.prepare("SELECT * FROM product_metadata").get();
  assert.equal(stored.product_type, "surface_cleaner");
  assert.equal(stored.classification_confidence, "high");
  assert.equal(stored.normalized_brand_key, "westinghouse");
  assert.equal(stored.brand_source, "verified_metadata");
  sqlite.close();
});

test("does not let incoming unknown metadata replace a verified or manual brand", () => {
  const sqlite = database();
  apply(sqlite, metadata({ rawBrand: "Old Brand", normalizedBrand: "Old Brand", normalizedBrandKey: "old-brand", brandAliasRuleId: "brand-old", brandSource: "manual_review" }));
  apply(sqlite, metadata({ rawBrand: null, normalizedBrand: null, normalizedBrandKey: null, brandAliasRuleId: null, brandSource: "unknown", lastSeenMarketDate: "2026-08-02" }));
  const stored = sqlite.prepare("SELECT normalized_brand_key, brand_source, last_seen_market_date FROM product_metadata").get();
  assert.deepEqual({ ...stored }, { normalized_brand_key: "old-brand", brand_source: "manual_review", last_seen_market_date: "2026-08-02" });
  sqlite.close();
});

test("replaces unknown brand metadata with verified metadata", () => {
  const sqlite = database();
  apply(sqlite, metadata());
  apply(sqlite, metadata({ rawBrand: "Westinghouse", normalizedBrand: "Westinghouse", normalizedBrandKey: "westinghouse", brandAliasRuleId: "brand-westinghouse", brandSource: "verified_metadata" }));
  const stored = sqlite.prepare("SELECT raw_brand, normalized_brand_key, brand_source FROM product_metadata").get();
  assert.deepEqual({ ...stored }, { raw_brand: "Westinghouse", normalized_brand_key: "westinghouse", brand_source: "verified_metadata" });
  sqlite.close();
});

test("applies a newer classification rule version without allowing an older rollback", () => {
  const sqlite = database();
  apply(sqlite, metadata({ productType: "surface_cleaner", classificationConfidence: "high", classificationRuleId: "old-accessory" }));
  applyBulk(sqlite, [metadata({ productType: "electric_pressure_washer", classificationConfidence: "high", classificationRuleId: "machine-electric", classificationRuleVersion: "product-rules-v2", classificationEvidence: ["TITLE_RULE:machine-electric"] })]);
  apply(sqlite, metadata({ productType: "hose", classificationConfidence: "high", classificationRuleId: "old-hose" }));
  const stored = sqlite.prepare("SELECT product_type, classification_rule_id, classification_rule_version FROM product_metadata").get();
  assert.deepEqual({ ...stored }, { product_type: "electric_pressure_washer", classification_rule_id: "machine-electric", classification_rule_version: "product-rules-v2" });
  sqlite.close();
});

test("binds metadata fields in the legacy bundle route order", () => {
  const sqlite = database();
  const row = metadata({
    productType: "hose", classificationConfidence: "medium", classificationRuleId: "hose-rule", classificationRuleVersion: "rules-v2",
    classificationEvidence: ["evidence"], rawBrand: "Brand", normalizedBrand: "Brand", normalizedBrandKey: "brand",
    brandAliasRuleId: "alias", brandSource: "verified_metadata", firstSeenMarketDate: "2026-07-01", lastSeenMarketDate: "2026-08-02",
  });
  const statement = buildProductMetadataUpsertStatement(d1(sqlite), row);
  assert.deepEqual(statement.values, ["AMAZON_US", "B000000001", "hose", "medium", "hose-rule", "rules-v2", "[\"evidence\"]", "Brand", "Brand", "brand", "alias", "verified_metadata", "2026-07-01", "2026-08-02"]);
  sqlite.close();
});

test("bulk upserts 131 metadata rows through one JSON parameter while preserving trusted brands, stronger classifications, and date bounds", () => {
  const sqlite = database();
  apply(sqlite, metadata({
    asin: "B000000001", productType: "surface_cleaner", classificationConfidence: "high", classificationRuleId: "surface-cleaner",
    classificationEvidence: ["TITLE_RULE:surface-cleaner"], rawBrand: "Manual Brand", normalizedBrand: "Manual Brand",
    normalizedBrandKey: "manual-brand", brandAliasRuleId: "brand-manual", brandSource: "manual_review",
    firstSeenMarketDate: "2026-08-01", lastSeenMarketDate: "2026-08-02",
  }));
  const rows = metadataRows(131, { firstSeenMarketDate: "2026-07-01", lastSeenMarketDate: "2026-09-01" });

  const statement = applyBulk(sqlite, rows);

  assert.equal(statement.values.length, 1);
  assert.ok(Buffer.byteLength(statement.sql, "utf8") < 100_000);
  assert.equal(sqlite.prepare("SELECT COUNT(*) AS count FROM product_metadata").get().count, 131);
  const retained = sqlite.prepare("SELECT product_type, classification_confidence, normalized_brand_key, brand_source, first_seen_market_date, last_seen_market_date FROM product_metadata WHERE asin = ?").get("B000000001");
  assert.deepEqual({ ...retained }, {
    product_type: "surface_cleaner", classification_confidence: "high", normalized_brand_key: "manual-brand", brand_source: "manual_review",
    first_seen_market_date: "2026-07-01", last_seen_market_date: "2026-09-01",
  });
  sqlite.close();
});

test("bulk upsert rejects the entire cohort for every conflicting trusted source pairing", () => {
  for (const existingSource of ["verified_metadata", "manual_review"]) {
    for (const incomingSource of ["verified_metadata", "manual_review"]) {
      const sqlite = database();
      apply(sqlite, metadata({
        asin: "B000000001", rawBrand: "Old Brand", normalizedBrand: "Old Brand",
        normalizedBrandKey: "old brand", brandSource: existingSource,
      }));
      const rows = [
        metadata({ asin: "B000000001", rawBrand: "Westinghouse", normalizedBrand: "Westinghouse", normalizedBrandKey: "westinghouse", brandAliasRuleId: "brand-westinghouse", brandSource: incomingSource }),
        metadata({ asin: "B000000002", rawBrand: "Other Brand", normalizedBrand: "Other Brand", normalizedBrandKey: "other brand", brandSource: incomingSource }),
      ];

      const result = buildProductMetadataBulkUpsertStatement(d1(sqlite), rows).run();

      assert.equal(result.changes, 0, `${existingSource} -> ${incomingSource}`);
      assert.equal(sqlite.prepare("SELECT normalized_brand_key FROM product_metadata WHERE asin = ?").get("B000000001").normalized_brand_key, "old brand");
      assert.equal(sqlite.prepare("SELECT COUNT(*) AS count FROM product_metadata WHERE asin = ?").get("B000000002").count, 0);
      sqlite.close();
    }
  }
});

test("bulk upsert permits same-key manual replay and unknown-to-trusted promotion", () => {
  const replayDatabase = database();
  apply(replayDatabase, metadata({ rawBrand: "Westinghouse", normalizedBrand: "Westinghouse", normalizedBrandKey: "westinghouse", brandAliasRuleId: "brand-westinghouse", brandSource: "verified_metadata" }));
  const replay = buildProductMetadataBulkUpsertStatement(d1(replayDatabase), [metadata({ rawBrand: "Westinghouse", normalizedBrand: "Westinghouse", normalizedBrandKey: "westinghouse", brandAliasRuleId: "brand-westinghouse", brandSource: "manual_review" })]).run();
  assert.equal(replay.changes, 1);
  assert.equal(replayDatabase.prepare("SELECT normalized_brand_key FROM product_metadata").get().normalized_brand_key, "westinghouse");
  replayDatabase.close();

  const promotionDatabase = database();
  apply(promotionDatabase, metadata());
  const promotion = buildProductMetadataBulkUpsertStatement(d1(promotionDatabase), [metadata({ rawBrand: "Westinghouse", normalizedBrand: "Westinghouse", normalizedBrandKey: "westinghouse", brandAliasRuleId: "brand-westinghouse", brandSource: "manual_review" })]).run();
  assert.equal(promotion.changes, 1);
  assert.equal(promotionDatabase.prepare("SELECT normalized_brand_key FROM product_metadata").get().normalized_brand_key, "westinghouse");
  promotionDatabase.close();
});

test("bulk upsert rejects trusted legacy rows with a missing normalized key", () => {
  for (const legacyKey of [null, ""]) {
    const sqlite = database();
    apply(sqlite, metadata({ rawBrand: "Legacy Brand", normalizedBrand: "Legacy Brand", normalizedBrandKey: legacyKey, brandSource: "manual_review" }));

    const result = buildProductMetadataBulkUpsertStatement(d1(sqlite), [metadata({ rawBrand: "Westinghouse", normalizedBrand: "Westinghouse", normalizedBrandKey: "westinghouse", brandAliasRuleId: "brand-westinghouse", brandSource: "verified_metadata" })]).run();

    assert.equal(result.changes, 0, `legacy key ${String(legacyKey)}`);
    assert.equal(sqlite.prepare("SELECT normalized_brand_key FROM product_metadata").get().normalized_brand_key, legacyKey);
    sqlite.close();
  }
});

test("classifies only the dedicated brand conflict guard constraint as a brand conflict", () => {
  assert.equal(isProductMetadataBrandConflictError(new Error("CHECK constraint failed: product_metadata_brand_conflict_guard_check")), true);
  assert.equal(isProductMetadataBrandConflictError(new Error("NOT NULL constraint failed: product_metadata.brand_source")), false);
  assert.equal(isProductMetadataBrandConflictError(new Error("database disk image is malformed")), false);
});
