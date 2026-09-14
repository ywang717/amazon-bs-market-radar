import assert from "node:assert/strict";
import test from "node:test";
import { productionCategoryRegistry } from "../lib/category-registry.ts";
import { normalizeTrustedBrand } from "../lib/brand-normalization.ts";
import { sanitizePublicStatus, validateProductMetadataRow, validateSyncBundle } from "../lib/sync-contract.ts";

const observations = Array.from({ length: 30 }, (_, index) => ({
  rank: index + 1,
  asin: `B${String(index + 1).padStart(9, "0")}`,
  title: `Product ${index + 1}`,
  url: `https://www.amazon.com/dp/B${String(index + 1).padStart(9, "0")}`,
  price: null,
  rating: 4.5,
  reviews: 100,
}));

const validBundleV1 = () => ({
  schemaVersion: "amazon-bs-dashboard-bundle-v1",
  marketDate: "2026-08-12",
  observedAt: "2026-08-12T00:00:00Z",
  receiptSha256: "a".repeat(64),
  categories: [{ key: "pressure_washers", sourceUrl: "https://www.amazon.com/zgbs/552856", observations }],
  reports: [],
});

const unknownMetadata = (asin) => ({
  marketplace: "AMAZON_US",
  asin,
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
  firstSeenMarketDate: "2026-08-12",
  lastSeenMarketDate: "2026-08-12",
});

const validBundleV2 = () => ({
  ...validBundleV1(),
  schemaVersion: "amazon-bs-dashboard-bundle-v2",
  productMetadata: observations.map(({ asin }) => unknownMetadata(asin)),
});

test("duplicate category keys are rejected before any market replacement", () => {
  const bundle = validBundleV1();
  bundle.categories.push(structuredClone(bundle.categories[0]));
  assert.equal(validateSyncBundle(bundle).ok, false);
});

test("sync category validation follows injected Registry and rejects unknown or disabled categories", () => {
  const registry = structuredClone(productionCategoryRegistry);
  registry.categories.push({ ...structuredClone(registry.categories[1]), categoryKey: "test_category", nodeId: "999999999" });
  const bundle = validBundleV1();
  bundle.categories[0].key = "test_category";
  assert.equal(validateSyncBundle(bundle, registry).ok, true);
  assert.equal(validateSyncBundle(bundle).ok, false);
  registry.categories.at(-1).enabled = false;
  assert.equal(validateSyncBundle(bundle, registry).ok, false);
  bundle.categories[0].key = "unknown_category";
  assert.equal(validateSyncBundle(bundle, registry).ok, false);
});

test("accepts a complete versioned sync bundle", () => {
  const result = validateSyncBundle(validBundleV1());

  assert.equal(result.ok, true);
  assert.equal(result.categories[0].quality.complete, true);
  assert.deepEqual(result.productMetadata, []);
});

test("accepts a v2 bundle with one coherent product metadata cohort", () => {
  const result = validateSyncBundle(validBundleV2());
  assert.equal(result.ok, true);
  assert.equal(result.productMetadata.length, 30);
});

test("exports the same complete product metadata validation used by v2 bundles", () => {
  assert.deepEqual(validateProductMetadataRow(unknownMetadata("B000000001")), unknownMetadata("B000000001"));
  assert.throws(() => validateProductMetadataRow({ ...unknownMetadata("B000000001"), brandSource: "unknown", rawBrand: "Invented" }));
});

test("enforces authoritative raw-brand normalization while accepting an audited alias", () => {
  const auditedAlias = {
    ...unknownMetadata("B000000001"),
    rawBrand: "Westinghouse Outdoor Power Equipment",
    normalizedBrand: "Westinghouse",
    normalizedBrandKey: "westinghouse",
    brandAliasRuleId: "brand-westinghouse",
    brandSource: "verified_metadata",
  };
  assert.deepEqual(validateProductMetadataRow(auditedAlias), auditedAlias);

  assert.throws(() => validateProductMetadataRow({
    ...auditedAlias,
    rawBrand: "Westinghouse",
    normalizedBrand: "Evil",
    normalizedBrandKey: "evil",
    brandAliasRuleId: null,
  }));
});

test("rejects brand text outside the portable PowerShell and JavaScript parity boundary", () => {
  for (const rawBrand of ["\uFEFFBrand", "\u0130Brand", "Brand\u0085Name"]) {
    assert.throws(() => normalizeTrustedBrand(rawBrand));
  }

  for (const row of [
    { rawBrand: "\uFEFFBrand", normalizedBrand: "Brand", normalizedBrandKey: "brand" },
    { rawBrand: "\u0130Brand", normalizedBrand: "\u0130Brand", normalizedBrandKey: "i\u0307brand" },
    { rawBrand: "Brand\u0085Name", normalizedBrand: "Brand\u0085Name", normalizedBrandKey: "brand\u0085name" },
  ]) {
    assert.throws(() => validateProductMetadataRow({
      ...unknownMetadata("B000000001"),
      ...row,
      brandAliasRuleId: null,
      brandSource: "verified_metadata",
    }));
  }
});

test("maps the audited KARCHER umlaut spelling to the portable brand contract", () => {
  assert.deepEqual(normalizeTrustedBrand("KÄRCHER"), {
    rawBrand: "KARCHER",
    normalizedBrand: "KARCHER",
    normalizedBrandKey: "karcher",
    brandAliasRuleId: null,
  });
});

test("accepts known product types only with medium or high confidence and a rule id", () => {
  for (const classificationConfidence of ["medium", "high"]) {
    const bundle = validBundleV2();
    bundle.productMetadata[0] = {
      ...bundle.productMetadata[0],
      productType: "electric_pressure_washer",
      classificationConfidence,
      classificationRuleId: "machine-electric",
      classificationEvidence: ["TITLE_RULE:machine-electric"],
    };
    assert.equal(validateSyncBundle(bundle).ok, true);
  }
});

test("accepts the finalized accessory Product Type vocabulary", () => {
  for (const productType of ["foam_cannon", "adapter_connector", "extension_wand", "sewer_jetter"]) {
    const row = {
      ...unknownMetadata("B000000001"),
      productType,
      classificationConfidence: "high",
      classificationRuleId: `accessory-${productType}`,
      classificationEvidence: [`TITLE_RULE:accessory-${productType}`],
    };
    assert.deepEqual(validateProductMetadataRow(row), row);
  }
});

test("rejects known product types with low confidence or a missing rule id", () => {
  for (const mutation of [
    { productType: "electric_pressure_washer", classificationConfidence: "low", classificationRuleId: "machine-electric" },
    { productType: "electric_pressure_washer", classificationConfidence: "medium", classificationRuleId: null },
    { productType: "electric_pressure_washer", classificationConfidence: "high", classificationRuleId: "   " },
  ]) {
    const bundle = validBundleV2();
    bundle.productMetadata[0] = { ...bundle.productMetadata[0], ...mutation };
    assert.equal(validateSyncBundle(bundle).ok, false);
  }
});

test("rejects unknown high confidence and every populated unknown-brand field", () => {
  for (const mutation of [
    { productType: "unknown", classificationConfidence: "high" },
    { brandSource: "unknown", rawBrand: "Invented" },
    { brandSource: "unknown", normalizedBrand: "Invented" },
    { brandSource: "unknown", normalizedBrandKey: "invented" },
    { brandSource: "unknown", brandAliasRuleId: "invented-alias" },
  ]) {
    const bundle = validBundleV2();
    bundle.productMetadata[0] = { ...bundle.productMetadata[0], ...mutation };
    assert.equal(validateSyncBundle(bundle).ok, false);
  }
});

test("rejects invalid metadata enums dates rules evidence and verified-brand shapes", () => {
  for (const mutation of [
    { marketplace: "AMAZON_UK" },
    { productType: "pressure_washer" },
    { classificationConfidence: "certain" },
    { classificationRuleId: 42 },
    { classificationRuleVersion: "" },
    { classificationEvidence: [] },
    { classificationEvidence: [""] },
    { rawBrand: 42 },
    { brandSource: "scraped_title" },
    { brandSource: "verified_metadata", rawBrand: null, normalizedBrand: "Brand", normalizedBrandKey: "brand" },
    { firstSeenMarketDate: "2026-02-31" },
    { firstSeenMarketDate: "2026-08-13", lastSeenMarketDate: "2026-08-12" },
  ]) {
    const bundle = validBundleV2();
    bundle.productMetadata[0] = { ...bundle.productMetadata[0], ...mutation };
    assert.equal(validateSyncBundle(bundle).ok, false);
  }

  const invalidObservedAt = validBundleV2();
  invalidObservedAt.observedAt = "2026-02-31T00:00:00Z";
  assert.equal(validateSyncBundle(invalidObservedAt).ok, false);
});

test("requires the metadata ASIN set to equal observation ASINs with unique marketplace-ASIN rows", () => {
  const missing = validBundleV2();
  missing.productMetadata.pop();
  assert.equal(validateSyncBundle(missing).ok, false);

  const extra = validBundleV2();
  extra.productMetadata.push(unknownMetadata("B999999999"));
  assert.equal(validateSyncBundle(extra).ok, false);

  const duplicate = validBundleV2();
  duplicate.productMetadata.push({ ...duplicate.productMetadata[0] });
  assert.equal(validateSyncBundle(duplicate).ok, false);
});
test("rejects impossible optional observation values", () => {
  const result = validateSyncBundle({ schemaVersion: "amazon-bs-dashboard-bundle-v1", marketDate: "2026-08-12", receiptSha256: "a".repeat(64), categories: [{ key: "pressure_washers", sourceUrl: "https://www.amazon.com/zgbs/552856", observations: observations.map((row, index) => index === 0 ? { ...row, price: -1, rating: 8, reviews: 1.5 } : row) }], reports: [] });
  assert.equal(result.ok, false);
});
test("rejects traversal report keys and non-Amazon observation URLs", () => {
  const result = validateSyncBundle({
    schemaVersion: "amazon-bs-dashboard-bundle-v1",
    marketDate: "2026-08-12",
    observedAt: "2026-08-12T00:00:00Z",
    receiptSha256: "a".repeat(64),
    categories: [{ key: "pressure_washers", sourceUrl: "https://www.amazon.com/zgbs/552856", observations: [{ ...observations[0], url: "https://evil.example/item" }] }],
    reports: [{ key: "../secret.pdf", categoryKey: "pressure_washers", kind: "daily", contentType: "application/pdf" }],
  });

  assert.equal(result.ok, false);
  assert.match(result.errors.join(" "), /Amazon|报告键/);
});

test("maps internal failures to one of three safe public states", () => {
  assert.deepEqual(sanitizePublicStatus({ current: true, complete: true, internalError: "C:\\Users\\secret" }), { label: "已更新", tone: "good" });
  assert.deepEqual(sanitizePublicStatus({ current: true, complete: false, internalError: "password=secret" }), { label: "数据不完整", tone: "warning" });
  assert.deepEqual(sanitizePublicStatus({ current: false, complete: false, internalError: "SMTP failed" }), { label: "数据延迟", tone: "danger" });
});
