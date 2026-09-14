import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { validateBrandMetadataRefreshRequest } from "../lib/brand-metadata-refresh-contract.ts";

const statuses = ["VERIFIED", "MISSING", "CONFLICT", "IDENTITY_MISMATCH", "VERIFICATION_BLOCKED"];
const sha256 = (value) => createHash("sha256").update(value, "utf8").digest("hex");
const asinSetHash = (asins) => sha256([...new Set(asins)].sort().join("\n"));

const artifact = {
  schema_version: "amazon-brand-enrichment-v1",
  marketplace: "AMAZON_US",
  generated_at: "2026-08-28T00:00:00Z",
  products: [
    { asin: "B000000001", detail_url: "https://www.amazon.com/dp/B000000001", verification_status: "VERIFIED", raw_brand: "Westinghouse", brand_source: "verified_metadata", evidence_source: "PRODUCT_OVERVIEW_BRAND_FIELD" },
    { asin: "B000000002", detail_url: "https://www.amazon.com/dp/B000000002", verification_status: "MISSING", raw_brand: null, brand_source: "unknown", evidence_source: null },
  ],
};

const metadata = (asin, brand = null) => ({
  marketplace: "AMAZON_US", asin, productType: "unknown", classificationConfidence: "low", classificationRuleId: null,
  classificationRuleVersion: "product-rules-v1", classificationEvidence: ["NO_SAFE_RULE_MATCH"], rawBrand: brand,
  normalizedBrand: brand, normalizedBrandKey: brand?.toLowerCase() ?? null, brandAliasRuleId: null,
  brandSource: brand === null ? "unknown" : "verified_metadata", firstSeenMarketDate: "2026-08-01", lastSeenMarketDate: "2026-08-28",
});

function validRequest() {
  // This deliberately uses non-canonical whitespace: parsing and re-stringifying it changes the bytes.
  const artifactJson = `\n${JSON.stringify(artifact, null, 2)}\n`;
  const artifactSha256 = sha256(artifactJson);
  return {
    schemaVersion: "amazon-brand-metadata-refresh-v1", marketplace: "AMAZON_US", artifactJson, artifactSha256,
    receipt: {
      schema_version: "amazon-brand-enrichment-receipt-v1", generated_at: "2026-08-28T00:00:00.0000000+00:00", marketplace: "AMAZON_US",
      requested_asin_set_sha256: asinSetHash(["B000000001", "B000000002"]), artifact_sha256: artifactSha256, record_count: 2,
      status_counts: Object.fromEntries(statuses.map((status) => [status, status === "VERIFIED" || status === "MISSING" ? 1 : 0])),
    },
    productMetadata: [{
      ...metadata("B000000001", "Westinghouse"),
      normalizedBrand: "Westinghouse",
      normalizedBrandKey: "westinghouse",
      brandAliasRuleId: "brand-westinghouse",
    }, metadata("B000000002")],
  };
}

function malformedArtifactRequest(products) {
  const request = validRequest();
  request.artifactJson = JSON.stringify({ ...artifact, products });
  request.artifactSha256 = sha256(request.artifactJson);
  request.receipt.artifact_sha256 = request.artifactSha256;
  request.receipt.record_count = Array.isArray(products) ? products.length : 0;
  request.receipt.status_counts = Object.fromEntries(statuses.map((status) => [status, 0]));
  request.receipt.requested_asin_set_sha256 = asinSetHash([]);
  request.productMetadata = [];
  return request;
}

test("accepts an exact UTF-8 artifact and full matching metadata cohort", async () => {
  const result = await validateBrandMetadataRefreshRequest(validRequest());
  assert.equal(result.ok, true);
  assert.equal(result.productMetadata.length, 2);
});

test("binds the hash to the supplied artifact JSON bytes rather than a re-serialized object", async () => {
  const request = validRequest();
  request.artifactJson = JSON.stringify(artifact);
  assert.equal((await validateBrandMetadataRefreshRequest(request)).ok, false);
});

test("returns a validation error instead of rejecting for non-array artifact products", async () => {
  const result = await validateBrandMetadataRefreshRequest(malformedArtifactRequest({}));
  assert.equal(result.ok, false);
  assert.match(result.errors.join(" "), /artifact products/);
});

test("returns a validation error instead of rejecting for null artifact products", async () => {
  const result = await validateBrandMetadataRefreshRequest(malformedArtifactRequest([null]));
  assert.equal(result.ok, false);
  assert.match(result.errors.join(" "), /artifact 产品无效/);
});

test("rejects forged receipt counts, hashes, and ASIN cohorts", async () => {
  for (const mutate of [
    (request) => { request.artifactSha256 = "0".repeat(64); },
    (request) => { request.receipt.artifact_sha256 = "0".repeat(64); },
    (request) => { request.receipt.record_count = 3; },
    (request) => { request.receipt.status_counts.VERIFIED = 2; },
    (request) => { request.receipt.requested_asin_set_sha256 = "0".repeat(64); },
    (request) => { request.productMetadata = [request.productMetadata[0]]; },
    (request) => { request.productMetadata.push(metadata("B000000003")); },
    (request) => { request.productMetadata.push({ ...request.productMetadata[0] }); },
  ]) {
    const request = validRequest();
    mutate(request);
    assert.equal((await validateBrandMetadataRefreshRequest(request)).ok, false);
  }
});

test("rejects brand values that are not the conservative artifact evidence", async () => {
  for (const mutate of [
    (request) => { request.productMetadata[0] = metadata("B000000001", "Invented Brand"); },
    (request) => { request.productMetadata[0] = { ...metadata("B000000001", "Westinghouse"), brandSource: "manual_review" }; },
    (request) => { request.productMetadata[1] = { ...metadata("B000000002"), rawBrand: "Inferred", normalizedBrand: "Inferred", normalizedBrandKey: "inferred", brandSource: "verified_metadata" }; },
  ]) {
    const request = validRequest();
    mutate(request);
    assert.equal((await validateBrandMetadataRefreshRequest(request)).ok, false);
  }
});

test("rejects forged normalized brand fields even when raw evidence hashes and receipts are valid", async () => {
  const request = validRequest();
  request.productMetadata[0] = {
    ...request.productMetadata[0],
    normalizedBrand: "Evil",
    normalizedBrandKey: "evil",
    brandAliasRuleId: null,
  };

  const result = await validateBrandMetadataRefreshRequest(request);

  assert.equal(result.ok, false);
  assert.match(result.errors.join(" "), /品牌归一化/);
});
