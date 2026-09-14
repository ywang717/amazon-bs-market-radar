import assert from "node:assert/strict";
import { register } from "node:module";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";

const workerEnvironment = globalThis.__dashboardWorkerEnvironment ??= {};
register(`data:text/javascript,export async function resolve(specifier, context, nextResolve) { if (specifier === "cloudflare:workers") return { url: "data:text/javascript,export const env = globalThis.__dashboardWorkerEnvironment", shortCircuit: true }; return nextResolve(specifier, context); }`, import.meta.url);

async function sha256(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function metadata(overrides = {}) {
  return {
    marketplace: "AMAZON_US", asin: "B000000001", productType: "unknown", classificationConfidence: "low", classificationRuleId: null,
    classificationRuleVersion: "product-rules-v1", classificationEvidence: ["NO_SAFE_RULE_MATCH"], rawBrand: "Westinghouse",
    normalizedBrand: "Westinghouse", normalizedBrandKey: "westinghouse", brandAliasRuleId: "brand-westinghouse",
    brandSource: "verified_metadata", firstSeenMarketDate: "2026-08-01", lastSeenMarketDate: "2026-08-02", ...overrides,
  };
}

function metadataRows(count) {
  return Array.from({ length: count }, (_, index) => metadata({ asin: `B${String(index + 1).padStart(9, "0")}` }));
}

async function payload(rows = [metadata()]) {
  const products = rows.map((row) => ({
    asin: row.asin, detail_url: `https://www.amazon.com/dp/${row.asin}`, verification_status: "VERIFIED", raw_brand: row.rawBrand,
    brand_source: "verified_metadata", evidence_source: "PRODUCT_OVERVIEW_BRAND_FIELD",
  })).sort((a, b) => a.asin.localeCompare(b.asin));
  const artifactJson = JSON.stringify({ schema_version: "amazon-brand-enrichment-v1", marketplace: "AMAZON_US", generated_at: "2026-08-03T00:00:00Z", products });
  const artifactSha256 = await sha256(artifactJson);
  const asinHash = await sha256(products.map((product) => product.asin).join("\n"));
  return {
    schemaVersion: "amazon-brand-metadata-refresh-v1", marketplace: "AMAZON_US", artifactJson, artifactSha256, productMetadata: rows,
    receipt: { schema_version: "amazon-brand-enrichment-receipt-v1", marketplace: "AMAZON_US", generated_at: "2026-08-03T00:00:00Z", artifact_sha256: artifactSha256, requested_asin_set_sha256: asinHash, record_count: products.length, status_counts: { VERIFIED: products.length, MISSING: 0, CONFLICT: 0, IDENTITY_MISMATCH: 0, VERIFICATION_BLOCKED: 0 } },
  };
}

function environment({ existing = [], maximumBinds = 100, maximumBatchStatements = 1, beforeBatch = null, initializeSchema = true } = {}) {
  const sqlite = new DatabaseSync(":memory:");
  if (initializeSchema) sqlite.exec(`CREATE TABLE product_metadata (marketplace TEXT NOT NULL, asin TEXT NOT NULL, product_type TEXT NOT NULL, classification_confidence TEXT NOT NULL, classification_rule_id TEXT, classification_rule_version TEXT NOT NULL, classification_evidence_json TEXT NOT NULL, raw_brand TEXT, normalized_brand TEXT, normalized_brand_key TEXT, brand_alias_rule_id TEXT, brand_source TEXT NOT NULL, first_seen_market_date TEXT NOT NULL, last_seen_market_date TEXT NOT NULL, PRIMARY KEY (marketplace, asin))`);
  for (const row of existing) sqlite.prepare("INSERT INTO product_metadata VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)").run(...row);
  const applicationBatches = [];
  const queries = [];
  function prepare(sql) {
    let values = [];
    return {
      sql,
      get values() { return values; },
      bind(...bound) { if (bound.length > maximumBinds) throw new Error(`D1 bind limit exceeded: ${bound.length}`); values = bound; return this; },
      async all() { queries.push({ sql, values: [...values] }); return { results: sqlite.prepare(sql).all(...values) }; },
      async first() { queries.push({ sql, values: [...values] }); return sqlite.prepare(sql).get(...values) ?? null; },
      async run() { return { meta: { changes: Number(sqlite.prepare(sql).run(...values).changes) } }; },
    };
  }
  return { SYNC_SECRET: "local-secret", ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) }, sqlite, applicationBatches, queries, DB: { prepare, async batch(statements) { const isSchemaBatch = statements.every((statement) => statement.sql.startsWith("CREATE")); if (!isSchemaBatch && statements.length > maximumBatchStatements) throw new Error(`D1 statement limit exceeded: ${statements.length}`); if (!isSchemaBatch) applicationBatches.push(statements); if (!isSchemaBatch && beforeBatch !== null) await beforeBatch(sqlite); sqlite.exec("BEGIN"); try { const results = []; for (const statement of statements) results.push(await statement.run()); sqlite.exec("COMMIT"); return results; } catch (error) { sqlite.exec("ROLLBACK"); throw error; } } } };
}

async function request(body, env, authorization = "Bearer local-secret") {
  for (const key of Reflect.ownKeys(workerEnvironment)) delete workerEnvironment[key];
  Object.assign(workerEnvironment, env);
  const workerUrl = new URL("../dist/server/index.js", import.meta.url); workerUrl.searchParams.set("test", `${Date.now()}-${Math.random()}`);
  const { default: worker } = await import(workerUrl.href);
  return worker.fetch(new Request("http://localhost/api/sync/v1/product-metadata", { method: "POST", headers: { authorization, "content-type": "application/json" }, body: JSON.stringify(body) }), env, { waitUntil() {}, passThroughOnException() {} });
}

test("requires the configured bearer token", async () => {
  const env = environment();
  assert.equal((await request(await payload(), env, "")).status, 401);
  assert.equal((await request(await payload(), env, "Bearer wrong")).status, 401);
  assert.equal(env.queries.length, 0);
  assert.equal(env.applicationBatches.length, 0);
  env.sqlite.close();
});

test("rejects an invalid refresh contract before querying or writing D1", async () => {
  const env = environment();
  const invalid = await payload(); invalid.artifactSha256 = "0".repeat(64);
  const response = await request(invalid, env);
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_product_metadata_refresh" });
  assert.equal(env.queries.length, 0);
  assert.equal(env.applicationBatches.length, 0);
  env.sqlite.close();
});

test("initializes an empty D1 schema before reading or writing product metadata", async () => {
  const env = environment({ initializeSchema: false });

  const response = await request(await payload(), env);

  assert.equal(response.status, 201);
  assert.equal(env.sqlite.prepare("SELECT COUNT(*) AS count FROM product_metadata").get().count, 1);
  env.sqlite.close();
});

test("rejects forged normalized brand metadata before querying or writing D1", async () => {
  const env = environment();
  const forged = await payload([metadata({ normalizedBrand: "Evil", normalizedBrandKey: "evil", brandAliasRuleId: null })]);

  const response = await request(forged, env);

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_product_metadata_refresh" });
  assert.equal(env.queries.length, 0);
  assert.equal(env.applicationBatches.length, 0);
  env.sqlite.close();
});

test("rejects a verified brand that conflicts with an existing verified or manual normalized key without a batch", async () => {
  for (const source of ["verified_metadata", "manual_review"]) {
    const existing = [["AMAZON_US", "B000000001", "unknown", "low", null, "rules-v1", "[]", "Old", "Old", "old-brand", "alias", source, "2026-01-01", "2026-08-01"]];
    const env = environment({ existing });
    const response = await request(await payload(), env);
    assert.equal(response.status, 409);
    assert.deepEqual(await response.json(), { error: "brand_metadata_conflict" });
    assert.equal(env.applicationBatches.length, 0);
    assert.equal(env.sqlite.prepare("SELECT normalized_brand_key FROM product_metadata").get().normalized_brand_key, "old-brand");
    env.sqlite.close();
  }
});

test("rejects trusted legacy rows with a missing normalized key without a batch", async () => {
  for (const legacyKey of [null, ""]) {
    const existing = [["AMAZON_US", "B000000001", "unknown", "low", null, "rules-v1", "[]", "Legacy Brand", "Legacy Brand", legacyKey, null, "manual_review", "2026-01-01", "2026-08-01"]];
    const env = environment({ existing });

    const response = await request(await payload(), env);

    assert.equal(response.status, 409, `legacy key ${String(legacyKey)}`);
    assert.deepEqual(await response.json(), { error: "brand_metadata_conflict" });
    assert.equal(env.applicationBatches.length, 0);
    assert.equal(env.sqlite.prepare("SELECT normalized_brand_key FROM product_metadata").get().normalized_brand_key, legacyKey);
    env.sqlite.close();
  }
});

test("rejects a stale-preflight trusted-brand conflict without partially writing its cohort", async () => {
  const rows = [
    metadata(),
    metadata({ asin: "B000000002", rawBrand: "Other Brand", normalizedBrand: "Other Brand", normalizedBrandKey: "other brand", brandAliasRuleId: null }),
  ];
  const env = environment({
    beforeBatch(sqlite) {
      sqlite.prepare("INSERT INTO product_metadata VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)").run(
        "AMAZON_US", "B000000001", "unknown", "low", null, "rules-v1", "[]",
        "Old Brand", "Old Brand", "old brand", null, "manual_review", "2026-01-01", "2026-08-01",
      );
    },
  });

  const response = await request(await payload(rows), env);

  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "brand_metadata_conflict" });
  assert.equal(env.queries.length, 1);
  assert.equal(env.applicationBatches.length, 1);
  assert.equal(env.sqlite.prepare("SELECT normalized_brand_key FROM product_metadata WHERE asin = ?").get("B000000001").normalized_brand_key, "old brand");
  assert.equal(env.sqlite.prepare("SELECT COUNT(*) AS count FROM product_metadata WHERE asin = ?").get("B000000002").count, 0);
  env.sqlite.close();
});

test("rejects a stale-preflight trusted legacy row with a null key without partially writing its cohort", async () => {
  const rows = [
    metadata(),
    metadata({ asin: "B000000002", rawBrand: "Other Brand", normalizedBrand: "Other Brand", normalizedBrandKey: "other brand", brandAliasRuleId: null }),
  ];
  const env = environment({
    beforeBatch(sqlite) {
      sqlite.prepare("INSERT INTO product_metadata VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)").run(
        "AMAZON_US", "B000000001", "unknown", "low", null, "rules-v1", "[]",
        "Legacy Brand", "Legacy Brand", null, null, "manual_review", "2026-01-01", "2026-08-01",
      );
    },
  });

  const response = await request(await payload(rows), env);

  assert.equal(response.status, 409);
  assert.equal(env.applicationBatches.length, 1);
  assert.equal(env.sqlite.prepare("SELECT normalized_brand_key FROM product_metadata WHERE asin = ?").get("B000000001").normalized_brand_key, null);
  assert.equal(env.sqlite.prepare("SELECT COUNT(*) AS count FROM product_metadata WHERE asin = ?").get("B000000002").count, 0);
  env.sqlite.close();
});

test("writes only metadata statements in one atomic batch and can insert a historical ASIN", async () => {
  const env = environment();
  const response = await request(await payload(), env);
  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { status: "imported", productMetadata: 1 });
  assert.equal(env.applicationBatches.length, 1);
  assert.equal(env.applicationBatches[0].length, 1);
  assert.equal(env.applicationBatches[0].every((statement) => /\bINSERT INTO product_metadata\b/i.test(statement.sql)), true);
  assert.equal(env.applicationBatches[0].some((statement) => /snapshots|category_days|observations|receipt/i.test(statement.sql)), false);
  const stored = env.sqlite.prepare("SELECT asin, normalized_brand_key, first_seen_market_date FROM product_metadata").get();
  assert.deepEqual({ ...stored }, { asin: "B000000001", normalized_brand_key: "westinghouse", first_seen_market_date: "2026-08-01" });
  env.sqlite.close();
});

test("imports 131 unique metadata rows with bounded D1 binds and one bulk statement", async () => {
  const rows = metadataRows(131);
  const env = environment({ maximumBinds: 100, maximumBatchStatements: 1 });

  const response = await request(await payload(rows), env);

  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { status: "imported", productMetadata: 131 });
  assert.equal(env.queries.length, 1);
  assert.ok(env.queries.every((query) => query.values.length <= 100));
  assert.equal(env.applicationBatches.length, 1);
  assert.equal(env.applicationBatches[0].length, 1);
  assert.equal(env.applicationBatches[0][0].values.length, 1);
  assert.match(env.applicationBatches[0][0].sql, /\bINSERT INTO product_metadata\b/i);
  assert.equal(env.sqlite.prepare("SELECT COUNT(*) AS count FROM product_metadata").get().count, 131);
  env.sqlite.close();
});
