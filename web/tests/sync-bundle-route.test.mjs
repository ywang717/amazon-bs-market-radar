import assert from "node:assert/strict";
import { register } from "node:module";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";

const workerEnvironment = globalThis.__dashboardWorkerEnvironment ??= {};
register(`data:text/javascript,export async function resolve(specifier, context, nextResolve) { if (specifier === "cloudflare:workers") return { url: "data:text/javascript,export const env = globalThis.__dashboardWorkerEnvironment", shortCircuit: true }; return nextResolve(specifier, context); }`, import.meta.url);

function completeBundle() {
  const categoryKeys = ["pressure_washers", "sump_pumps", "pressure_washer_accessories"];
  return {
    schemaVersion: "amazon-bs-dashboard-bundle-v1",
    marketDate: "2026-08-13",
    observedAt: "2026-08-14T06:50:00Z",
    receiptSha256: "b".repeat(64),
    categories: categoryKeys.map((key) => ({
      key,
      sourceUrl: `https://www.amazon.com/zgbs/${key}`,
      observations: Array.from({ length: 30 }, (_, index) => ({
        rank: index + 1,
        asin: `B${key.slice(0, 2).toUpperCase()}${String(index + 1).padStart(7, "0")}`,
        title: `${key} ${index + 1}`,
        url: `https://www.amazon.com/dp/B${key.slice(0, 2).toUpperCase()}${String(index + 1).padStart(7, "0")}`,
        price: 20,
        rating: 4.5,
        reviews: 100,
      })),
    })),
    reports: [],
  };
}

function completeBundleV2() {
  const bundle = completeBundle();
  const uniqueAsins = [...new Set(bundle.categories.flatMap((category) => category.observations.map(({ asin }) => asin)))];
  return {
    ...bundle,
    schemaVersion: "amazon-bs-dashboard-bundle-v2",
    productMetadata: uniqueAsins.map((asin) => ({
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
      firstSeenMarketDate: bundle.marketDate,
      lastSeenMarketDate: bundle.marketDate,
    })),
  };
}

function withIdentity(bundle, marketDate, receiptCharacter) {
  return {
    ...bundle,
    marketDate,
    observedAt: `${marketDate}T12:00:00Z`,
    receiptSha256: receiptCharacter.repeat(64),
    productMetadata: bundle.productMetadata.map((metadata) => ({
      ...metadata,
      firstSeenMarketDate: marketDate,
      lastSeenMarketDate: marketDate,
    })),
  };
}

function existingMarketDateEnvironment() {
  const DB = {
    prepare(sql) {
      let values = [];
      return {
        sql,
        get values() { return values; },
        bind(...bound) { values = bound; return this; },
        async first() { return null; },
      };
    },
    async batch(statements) {
      if (statements.every((statement) => statement.sql.startsWith("CREATE"))) return [];
      const insertIndex = statements.findIndex((statement) => statement.sql.startsWith("INSERT INTO snapshots"));
      const deleteIndex = statements.findIndex((statement) => statement.sql.startsWith("DELETE FROM snapshots") && statement.values[0] === "2026-08-13");
      if (insertIndex >= 0 && (deleteIndex < 0 || deleteIndex > insertIndex)) throw new Error("UNIQUE constraint failed: snapshots.market_date");
      return [];
    },
  };
  return { DB, SYNC_SECRET: "local-secret", ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } };
}

function sameReceiptEnvironment() {
  const statements = [];
  const batches = [];
  const DB = {
    prepare(sql) {
      let values = [];
      return {
        sql,
        get values() { return values; },
        bind(...bound) { values = bound; return this; },
        async first() { return sql.includes("receipt_sha256") ? { market_date: "2026-08-13" } : null; },
      };
    },
    async batch(batch) {
      if (!batch.every((statement) => statement.sql.startsWith("CREATE"))) batches.push(batch);
      statements.push(...batch);
      return [];
    },
  };
  return { DB, SYNC_SECRET: "local-secret", ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) }, statements, batches };
}

function sqliteEnvironment({ failProductMetadata = false, failWithOrdinaryBrandSourceNotNull = false, beforeApplicationBatch = null } = {}) {
  const database = new DatabaseSync(":memory:");
  const applicationBatches = [];
  const DB = {
    prepare(sql) {
      let values = [];
      return {
        sql,
        get values() { return values; },
        bind(...bound) { values = bound; return this; },
        async first() { return database.prepare(sql).get(...values) ?? null; },
      };
    },
    async batch(statements) {
      const isSchemaBatch = statements.every((statement) => statement.sql.startsWith("CREATE"));
      if (!isSchemaBatch) applicationBatches.push(statements);
      if (!isSchemaBatch && beforeApplicationBatch !== null) await beforeApplicationBatch(database);
      database.exec("BEGIN");
      try {
        for (const statement of statements) {
          if (failProductMetadata && /^INSERT INTO product_metadata/i.test(statement.sql)) throw new Error("simulated metadata failure");
          if (failWithOrdinaryBrandSourceNotNull && /^INSERT INTO product_metadata/i.test(statement.sql)) throw new Error("NOT NULL constraint failed: product_metadata.brand_source");
          database.prepare(statement.sql).run(...statement.values);
        }
        database.exec("COMMIT");
      } catch (error) {
        database.exec("ROLLBACK");
        throw error;
      }
      return [];
    },
  };
  return { DB, database, applicationBatches, SYNC_SECRET: "local-secret", ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } };
}

async function request(bundle, env) {
  for (const key of Reflect.ownKeys(workerEnvironment)) delete workerEnvironment[key];
  Object.assign(workerEnvironment, env);
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}-${Math.random()}`);
  const { default: worker } = await import(workerUrl.href);
  return worker.fetch(new Request("http://localhost/api/sync/v1/bundles", {
    method: "POST",
    headers: { authorization: "Bearer local-secret", "content-type": "application/json" },
    body: JSON.stringify(bundle),
  }), env, { waitUntil() {}, passThroughOnException() {} });
}

test("atomically replaces a previously imported market date when its verified receipt changes", async () => {
  const response = await request(completeBundle(), existingMarketDateEnvironment());
  assert.equal(response.status, 201);
  const body = await response.json();
  assert.equal(body.status, "imported");
  assert.equal(body.marketDate, "2026-08-13");
  assert.equal(body.observations, 90);
});

test("single-market recovery preserves other markets and their receipt provenance", async () => {
  const env = sqliteEnvironment();
  try {
    const initial = completeBundle();
    assert.equal((await request(initial, env)).status, 201);
    const untouched = env.database.prepare("SELECT * FROM observations WHERE category_key = 'sump_pumps' ORDER BY rank").all();
    const partial = { ...initial, receiptSha256: "c".repeat(64), observedAt: "2026-08-14T07:00:00Z", categories: [initial.categories[0]] };
    assert.equal((await request(partial, env)).status, 201);
    assert.equal(env.database.prepare("SELECT count(*) AS n FROM observations").get().n, 90);
    assert.deepEqual(env.database.prepare("SELECT * FROM observations WHERE category_key = 'sump_pumps' ORDER BY rank").all(), untouched);
    assert.equal(env.database.prepare("SELECT receipt_sha256 FROM category_capture_receipts WHERE category_key = 'sump_pumps'").get().receipt_sha256, "b".repeat(64));
    assert.equal(env.database.prepare("SELECT receipt_sha256 FROM category_capture_receipts WHERE category_key = 'pressure_washers'").get().receipt_sha256, "c".repeat(64));
    assert.equal(env.database.prepare("SELECT complete_category_count FROM snapshots").get().complete_category_count, 3);
    assert.notEqual(env.database.prepare("SELECT receipt_sha256 FROM snapshots").get().receipt_sha256, partial.receiptSha256);
  } finally { env.database.close(); }
});

test("an incomplete retry cannot downgrade a complete category", async () => {
  const env = sqliteEnvironment();
  try {
    const initial = completeBundle();
    assert.equal((await request(initial, env)).status, 201);
    const partial = { ...initial, receiptSha256: "c".repeat(64), categories: [{ ...initial.categories[0], observations: initial.categories[0].observations.slice(0, 29) }] };
    assert.equal((await request(partial, env)).status, 409);
    assert.equal(env.database.prepare("SELECT count(*) AS n FROM observations").get().n, 90);
  } finally { env.database.close(); }
});

test("a stale category capture cannot replace newer rows", async () => {
  const env = sqliteEnvironment();
  try {
    const initial = completeBundle();
    assert.equal((await request(initial, env)).status, 201);
    const stale = { ...initial, receiptSha256: "c".repeat(64), observedAt: "2026-08-14T06:00:00Z", categories: [initial.categories[0]] };
    assert.equal((await request(stale, env)).status, 409);
    assert.equal(env.database.prepare("SELECT receipt_sha256 FROM snapshots").get().receipt_sha256, initial.receiptSha256);
  } finally { env.database.close(); }
});

test("reimports the same verified receipt for its original market date to backfill new fields", async () => {
  const env = sameReceiptEnvironment();
  const response = await request(completeBundle(), env);

  assert.equal(response.status, 201);
  assert.equal((await response.json()).status, "imported");
  assert.equal(env.statements.some((statement) => statement.sql.startsWith("DELETE FROM observations")), true);
  assert.equal(env.statements.some((statement) => /^INSERT INTO product_metadata/i.test(statement.sql)), false);
});

test("writes snapshot observations discounts and product metadata in one application batch", async () => {
  const env = sameReceiptEnvironment();
  const response = await request(completeBundleV2(), env);

  assert.equal(response.status, 201);
  assert.equal(env.batches.length, 1);
  assert.ok(env.batches[0].some((statement) => /^INSERT INTO product_metadata/i.test(statement.sql)));
  assert.ok(env.batches[0].some((statement) => /^INSERT INTO snapshots/i.test(statement.sql)));
  assert.ok(env.batches[0].some((statement) => /^INSERT INTO category_days/i.test(statement.sql)));
  assert.ok(env.batches[0].some((statement) => /^INSERT INTO observations/i.test(statement.sql)));
  assert.ok(env.batches[0].some((statement) => /^INSERT INTO observation_discounts/i.test(statement.sql)));
});

test("rolls back snapshot and metadata together when a v2 metadata write fails", async () => {
  const env = sqliteEnvironment({ failProductMetadata: true });
  let failed = false;
  try {
    const response = await request(completeBundleV2(), env);
    failed = response.status >= 500;
  } catch {
    failed = true;
  }

  assert.equal(failed, true);
  assert.equal(env.database.prepare("SELECT count(*) AS count FROM snapshots").get().count, 0);
  assert.equal(env.database.prepare("SELECT count(*) AS count FROM product_metadata").get().count, 0);
  env.database.close();
});

test("does not misclassify an ordinary product metadata database failure as a brand conflict", async () => {
  const env = sqliteEnvironment({ failWithOrdinaryBrandSourceNotNull: true });
  let response;
  try {
    response = await request(completeBundleV2(), env);
  } catch {
    response = null;
  }

  assert.notEqual(response?.status, 409);
  assert.equal(env.database.prepare("SELECT COUNT(*) AS count FROM snapshots").get().count, 0);
  assert.equal(env.database.prepare("SELECT COUNT(*) AS count FROM product_metadata").get().count, 0);
  env.database.close();
});

test("rejects every trusted brand conflict source pairing without partial bundle writes", async () => {
  for (const existingSource of ["verified_metadata", "manual_review"]) {
    for (const incomingSource of ["verified_metadata", "manual_review"]) {
      const bundle = completeBundleV2();
      const target = bundle.productMetadata[0];
      bundle.productMetadata[0] = {
        ...target,
        rawBrand: "Westinghouse",
        normalizedBrand: "Westinghouse",
        normalizedBrandKey: "westinghouse",
        brandAliasRuleId: "brand-westinghouse",
        brandSource: incomingSource,
      };
      const env = sqliteEnvironment({
        beforeApplicationBatch(database) {
          database.prepare("INSERT INTO product_metadata VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)").run(
            "AMAZON_US", target.asin, "unknown", "low", null, "rules-v1", "[]",
            "Old Brand", "Old Brand", "old brand", null, existingSource, "2026-01-01", "2026-08-01",
          );
        },
      });

      const response = await request(bundle, env);

      assert.equal(response.status, 409, `${existingSource} -> ${incomingSource}`);
      assert.deepEqual(await response.json(), { error: "brand_metadata_conflict" });
      assert.equal(env.database.prepare("SELECT COUNT(*) AS count FROM snapshots").get().count, 0);
      assert.equal(env.database.prepare("SELECT COUNT(*) AS count FROM observations").get().count, 0);
      assert.equal(env.database.prepare("SELECT normalized_brand_key FROM product_metadata WHERE asin = ?").get(target.asin).normalized_brand_key, "old brand");
      env.database.close();
    }
  }
});

test("allows same-key trusted replay and unknown-to-trusted promotion in a v2 bundle", async () => {
  for (const scenario of [
    { existingSource: "verified_metadata", existingKey: "westinghouse", incomingSource: "manual_review" },
    { existingSource: "unknown", existingKey: null, incomingSource: "verified_metadata" },
  ]) {
    const bundle = completeBundleV2();
    const target = bundle.productMetadata[0];
    bundle.productMetadata[0] = {
      ...target,
      rawBrand: "Westinghouse",
      normalizedBrand: "Westinghouse",
      normalizedBrandKey: "westinghouse",
      brandAliasRuleId: "brand-westinghouse",
      brandSource: scenario.incomingSource,
    };
    const env = sqliteEnvironment({
      beforeApplicationBatch(database) {
        database.prepare("INSERT INTO product_metadata VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)").run(
          "AMAZON_US", target.asin, "unknown", "low", null, "rules-v1", "[]",
          scenario.existingKey === null ? null : "Westinghouse",
          scenario.existingKey === null ? null : "Westinghouse",
          scenario.existingKey,
          scenario.existingKey === null ? null : "brand-westinghouse",
          scenario.existingSource, "2026-01-01", "2026-08-01",
        );
      },
    });

    const response = await request(bundle, env);

    assert.equal(response.status, 201);
    assert.equal(env.database.prepare("SELECT normalized_brand_key FROM product_metadata WHERE asin = ?").get(target.asin).normalized_brand_key, "westinghouse");
    assert.equal(env.database.prepare("SELECT COUNT(*) AS count FROM snapshots").get().count, 1);
    env.database.close();
  }
});

test("rejects trusted legacy metadata with a missing normalized key without partial bundle writes", async () => {
  for (const legacyKey of [null, ""]) {
    const bundle = completeBundleV2();
    const target = bundle.productMetadata[0];
    bundle.productMetadata[0] = {
      ...target,
      rawBrand: "Westinghouse",
      normalizedBrand: "Westinghouse",
      normalizedBrandKey: "westinghouse",
      brandAliasRuleId: "brand-westinghouse",
      brandSource: "verified_metadata",
    };
    const env = sqliteEnvironment({
      beforeApplicationBatch(database) {
        database.prepare("INSERT INTO product_metadata VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)").run(
          "AMAZON_US", target.asin, "unknown", "low", null, "rules-v1", "[]",
          "Legacy Brand", "Legacy Brand", legacyKey, null, "manual_review", "2026-01-01", "2026-08-01",
        );
      },
    });

    const response = await request(bundle, env);

    assert.equal(response.status, 409, `legacy key ${String(legacyKey)}`);
    assert.equal(env.database.prepare("SELECT COUNT(*) AS count FROM snapshots").get().count, 0);
    assert.equal(env.database.prepare("SELECT normalized_brand_key FROM product_metadata WHERE asin = ?").get(target.asin).normalized_brand_key, legacyKey);
    env.database.close();
  }
});

test("preserves metadata quality while merging first and last seen dates", async () => {
  const env = sqliteEnvironment();
  const base = completeBundleV2();
  const targetAsin = base.productMetadata[0].asin;
  assert.equal((await request(base, env)).status, 201);

  const medium = withIdentity(completeBundleV2(), "2026-08-14", "c");
  medium.productMetadata[0] = {
    ...medium.productMetadata[0],
    productType: "other_accessory",
    classificationConfidence: "medium",
    classificationRuleId: "accessory-other",
    classificationEvidence: ["TITLE_RULE:accessory-other"],
    rawBrand: "Westinghouse",
    normalizedBrand: "Westinghouse",
    normalizedBrandKey: "westinghouse",
    brandAliasRuleId: "brand-westinghouse",
    brandSource: "verified_metadata",
  };
  assert.equal((await request(medium, env)).status, 201);

  const lowerAndEarlier = withIdentity(completeBundleV2(), "2026-08-11", "d");
  lowerAndEarlier.productMetadata[0] = {
    ...lowerAndEarlier.productMetadata[0],
    productType: "unknown",
    classificationConfidence: "low",
    classificationRuleId: null,
    classificationEvidence: ["NO_SAFE_RULE_MATCH"],
  };
  assert.equal((await request(lowerAndEarlier, env)).status, 201);

  const lowerRow = env.database.prepare("SELECT * FROM product_metadata WHERE marketplace = ? AND asin = ?").get("AMAZON_US", targetAsin);
  assert.equal(lowerRow.product_type, "other_accessory");
  assert.equal(lowerRow.classification_confidence, "medium");
  assert.equal(lowerRow.classification_rule_id, "accessory-other");
  assert.equal(lowerRow.first_seen_market_date, "2026-08-11");

  const equalAndLater = withIdentity(completeBundleV2(), "2026-08-15", "e");
  equalAndLater.productMetadata[0] = {
    ...equalAndLater.productMetadata[0],
    productType: "nozzle",
    classificationConfidence: "medium",
    classificationRuleId: "accessory-nozzle",
    classificationEvidence: ["TITLE_RULE:accessory-nozzle"],
  };
  assert.equal((await request(equalAndLater, env)).status, 201);

  const high = withIdentity(completeBundleV2(), "2026-08-16", "f");
  high.productMetadata[0] = {
    ...high.productMetadata[0],
    productType: "electric_pressure_washer",
    classificationConfidence: "high",
    classificationRuleId: "machine-electric",
    classificationEvidence: ["TITLE_RULE:machine-electric"],
  };
  assert.equal((await request(high, env)).status, 201);

  const lowerThanHigh = withIdentity(completeBundleV2(), "2026-08-17", "1");
  lowerThanHigh.productMetadata[0] = {
    ...lowerThanHigh.productMetadata[0],
    productType: "hose",
    classificationConfidence: "medium",
    classificationRuleId: "accessory-hose",
    classificationEvidence: ["TITLE_RULE:accessory-hose"],
  };
  assert.equal((await request(lowerThanHigh, env)).status, 201);

  const row = env.database.prepare("SELECT * FROM product_metadata WHERE marketplace = ? AND asin = ?").get("AMAZON_US", targetAsin);
  assert.equal(row.product_type, "electric_pressure_washer");
  assert.equal(row.classification_confidence, "high");
  assert.equal(row.classification_rule_id, "machine-electric");
  assert.equal(row.classification_evidence_json, '["TITLE_RULE:machine-electric"]');
  assert.equal(row.raw_brand, "Westinghouse");
  assert.equal(row.brand_source, "verified_metadata");
  assert.equal(row.first_seen_market_date, "2026-08-11");
  assert.equal(row.last_seen_market_date, "2026-08-17");
  env.database.close();
});
