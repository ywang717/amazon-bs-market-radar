import assert from "node:assert/strict";
import test from "node:test";
import { categories } from "../lib/catalog.ts";
import { loadLiveDashboard, loadLiveProduct } from "../lib/live-dashboard-data.ts";
import { createD1DashboardStore } from "../lib/dashboard-store.ts";
import { buildAnalyticalCategory, buildMarketSignals, buildMarketState } from "../lib/ui-intelligence.ts";

function observation(marketDate, category, rank) {
  const asin = `${category.key.slice(0, 3).toUpperCase()}${String(rank).padStart(7, "0")}`;
  return {
    market_date: marketDate,
    category_key: category.key,
    rank,
    asin,
    title: `${category.short} ${rank}`,
    url: `https://www.amazon.com/dp/${asin}`,
    price: 20,
    rating: 4.5,
    reviews: 100,
  };
}

function completeStore(dates) {
  const snapshots = dates.map((market_date) => ({
    market_date,
    observed_at: `${market_date}T09:00:00Z`,
    complete_category_count: 3,
  }));
  const categoryDays = dates.flatMap((market_date) => categories.map((category) => ({
    market_date,
    category_key: category.key,
    observation_count: 30,
    complete: 1,
    missing_ranks_json: "[]",
  })));
  const observations = dates.flatMap((marketDate) => categories.flatMap((category) =>
    Array.from({ length: 30 }, (_, index) => observation(marketDate, category, index + 1)),
  ));
  const productMetadata = [{
    marketplace: "AMAZON_US",
    asin: observations[0]?.asin ?? "PRE0000001",
    productType: "electric_pressure_washer",
    classificationConfidence: "high",
    classificationRuleId: "pressure-washer-v1",
    classificationRuleVersion: "1",
    classificationEvidence: ["title"],
    rawBrand: "Example",
    normalizedBrand: "Example",
    normalizedBrandKey: "example",
    brandAliasRuleId: null,
    brandSource: "verified_metadata",
    firstSeenMarketDate: dates[0] ?? "2026-08-13",
    lastSeenMarketDate: dates.at(-1) ?? "2026-08-13",
  }];
  return {
    snapshots,
    categoryDays,
    observations,
    productMetadata,
    async listSnapshots() { return this.snapshots; },
    async listCategoryDays() { return this.categoryDays; },
    async listObservations() { return this.observations; },
    async listProductHistory(asin) { return this.observations.filter((row) => row.asin === asin); },
    async listProductMetadata() { return this.productMetadata; },
    async listProductMetadataByAsins(asins) { return this.productMetadata.filter((row) => asins.includes(row.asin)); },
  };
}

function failingStore() {
  return {
    async listSnapshots() { throw new Error("D1 unavailable"); },
    async listCategoryDays() { throw new Error("D1 unavailable"); },
    async listObservations() { throw new Error("D1 unavailable"); },
    async listProductHistory() { throw new Error("D1 unavailable"); },
    async listProductMetadata() { throw new Error("D1 unavailable"); },
    async listProductMetadataByAsins() { throw new Error("D1 unavailable"); },
  };
}

function emptyProductStoreWithSnapshots() {
  const store = completeStore(["2026-08-13"]);
  store.observations = [];
  return store;
}

test("uses the newest complete D1 market day instead of the seed snapshot", async () => {
  const store = completeStore(["2026-08-12", "2026-08-13"]);
  const data = await loadLiveDashboard({ store });

  assert.equal(data.source, "d1");
  assert.equal(data.marketDate, "2026-08-13");
  assert.equal(data.totalObservations, 90);
  assert.equal(data.completeCategories, 3);
  assert.equal(data.completeMarketDays, 2);
  assert.equal(data.categoryRows.every((row) => row.comparison.ready), true);
  assert.equal((await store.listProductMetadata()).length, 1);
});

test("keeps analysis on the latest valid category day when a newer snapshot is incomplete", async () => {
  const store = completeStore(["2026-08-12", "2026-08-13"]);
  store.observations = store.observations.filter((row) => !(row.market_date === "2026-08-13" && row.category_key === "sump_pumps" && row.rank === 30));
  const data = await loadLiveDashboard({ store });
  const sump = data.categoryRows.find((row) => row.key === "sump_pumps");

  assert.equal(data.latestSnapshotDate, "2026-08-13");
  assert.equal(sump.marketDate, "2026-08-12");
  assert.equal(sump.quality.complete, true);
  assert.equal(sump.observations.length, 30);
  assert.equal(sump.comparison.ready, false);
});

test("suppresses ranking movement evidence when complete Top 30 lists have no ASIN overlap", async () => {
  const store = completeStore(["2026-08-12", "2026-08-13"]);
  store.observations = store.observations.map((row) => row.market_date === "2026-08-13" && row.category_key === "sump_pumps"
    ? { ...row, asin: `NEW${String(row.rank).padStart(7, "0")}` }
    : row);
  const data = await loadLiveDashboard({ store });
  const sump = data.categoryRows.find((row) => row.key === "sump_pumps");

  assert.equal(sump.quality.complete, true);
  assert.equal(sump.comparison.ready, false);
  assert.equal(sump.comparison.averageAbsoluteMove, null);
  assert.equal(sump.comparison.maxAbsoluteMove, null);
  assert.equal(sump.comparison.entries, 30);
  assert.equal(sump.comparison.exits, 30);
});

test("does not analyze a day whose persisted category status is incomplete", async () => {
  const store = completeStore(["2026-08-12", "2026-08-13"]);
  const day = store.categoryDays.find((row) => row.market_date === "2026-08-13" && row.category_key === "sump_pumps");
  day.complete = 0;
  const data = await loadLiveDashboard({ store });
  const sump = data.categoryRows.find((row) => row.key === "sump_pumps");

  assert.equal(sump.marketDate, "2026-08-12");
  assert.equal(sump.observations.length, 30);
  assert.equal(sump.quality.complete, true);
  assert.equal(sump.comparison.ready, false);
});

test("falls back as one complete dataset when D1 is unavailable", async () => {
  const data = await loadLiveDashboard({ store: failingStore() });

  assert.equal(data.source, "seed_fallback");
  assert.equal(data.marketDate, "2026-08-12");
  assert.equal(data.totalObservations, 90);
});

test("keeps live ranking data when optional product metadata is unavailable", async () => {
  const store = completeStore(["2026-08-12", "2026-08-13"]);
  store.listProductMetadata = async () => { throw new Error("metadata unavailable"); };

  const data = await loadLiveDashboard({ store });

  assert.equal(data.source, "d1");
  assert.equal(data.marketDate, "2026-08-13");
  assert.equal(data.totalObservations, 90);
  assert.deepEqual(data.productMetadata, []);
  assert.equal(data.metadataAvailable, false);
});

test("does not return a seed product when D1 works but the ASIN is absent", async () => {
  const result = await loadLiveProduct("B0BVGSX46M", { store: emptyProductStoreWithSnapshots(), context: { marketplace: "US", category: "pressure_washers", segment: "all" } });

  assert.deepEqual(result, { status: "not_found" });
});

test("uses the verified seed product when a reachable D1 store is empty", async () => {
  const emptyStore = completeStore([]);
  const result = await loadLiveProduct("B0BVGSX46M", { store: emptyStore, context: { marketplace: "US", category: "pressure_washers", segment: "all" } });

  assert.equal(result.status, "found");
  assert.equal(result.source, "seed_fallback");
});

test("skips an incomplete day and compares with the previous valid market day", async () => {
  const store = completeStore(["2026-08-10", "2026-08-11", "2026-08-12"]);
  store.categoryDays = store.categoryDays.map((row) => row.market_date === "2026-08-11" && row.category_key === "pressure_washers" ? { ...row, complete: 0 } : row);
  const data = await loadLiveDashboard({ store });
  const washer = data.categoryRows.find((row) => row.key === "pressure_washers");

  assert.equal(washer.comparison.baselineDate, "2026-08-10");
  assert.equal(washer.comparison.ready, true);
  assert.equal(data.previousComparableDate, null);
});

test("keeps exits turnover and brand contraction on the latest valid pair across incomplete and failed days", async () => {
  const store = completeStore(["2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13"]);
  store.observations = store.observations.map((row) => row.category_key === "pressure_washers" && row.market_date >= "2026-08-12"
    ? { ...row, asin: `BAD${row.market_date.replaceAll("-", "")}${String(row.rank).padStart(2, "0")}` }
    : row);
  store.categoryDays = store.categoryDays
    .filter((row) => !(row.market_date === "2026-08-13" && row.category_key === "pressure_washers"))
    .map((row) => row.market_date === "2026-08-12" && row.category_key === "pressure_washers" ? { ...row, complete: 0 } : row);
  const washerRows = store.observations.filter(({ category_key }) => category_key === "pressure_washers");
  store.productMetadata = [...new Map(washerRows.map((row) => [row.asin, row])).values()].map((row) => ({
    marketplace: "AMAZON_US",
    asin: row.asin,
    productType: "electric_pressure_washer",
    classificationConfidence: "high",
    classificationRuleId: "machine-electric",
    classificationRuleVersion: "product-rules-v1",
    classificationEvidence: ["title"],
    rawBrand: row.asin.startsWith("BAD") ? "Incomplete Brand" : "Stable Brand",
    normalizedBrand: row.asin.startsWith("BAD") ? "Incomplete Brand" : "Stable Brand",
    normalizedBrandKey: row.asin.startsWith("BAD") ? "incomplete-brand" : "stable-brand",
    brandAliasRuleId: null,
    brandSource: "verified_metadata",
    firstSeenMarketDate: "2026-08-10",
    lastSeenMarketDate: "2026-08-13",
  }));

  const data = await loadLiveDashboard({ store });
  const rawWasher = data.categoryRows.find(({ key }) => key === "pressure_washers");
  const analytical = buildAnalyticalCategory(rawWasher, data.productMetadata, {
    marketplace: "US", category: "pressure_washers", segment: "machines",
  });
  const signals = buildMarketSignals({ categoryRows: [analytical], productMetadata: data.productMetadata });

  assert.equal(data.latestSnapshotDate, "2026-08-13");
  assert.equal(rawWasher.latestSnapshotComplete, false);
  assert.equal(analytical.marketDate, "2026-08-11");
  assert.equal(analytical.comparison.baselineDate, "2026-08-10");
  assert.deepEqual(analytical.history.map(({ marketDate }) => marketDate), ["2026-08-10", "2026-08-11"]);
  assert.equal(analytical.comparison.exits, 0);
  assert.equal(buildMarketState(analytical).turnover, "LOW");
  assert.equal(signals.some(({ kind }) => kind === "top10_exit" || kind === "top30_exit"), false);
  assert.equal(signals.some(({ kind }) => kind === "brand_contraction"), false);
  assert.equal(signals.some(({ asin }) => asin?.startsWith("BAD")), false);
});

test("excludes a product history observation from a persisted-incomplete category day", async () => {
  const store = completeStore(["2026-08-10", "2026-08-11"]);
  store.observations = store.observations.map((row) => row.category_key === "pressure_washers"
    ? row
    : { ...row, asin: `OTHER${row.category_key.slice(0, 3).toUpperCase()}${String(row.rank).padStart(6, "0")}` });
  store.categoryDays = store.categoryDays.map((row) => row.market_date === "2026-08-11" && row.category_key === "pressure_washers" ? { ...row, complete: 0 } : row);

  const result = await loadLiveProduct("PRE0000001", { store, context: { marketplace: "US", category: "pressure_washers", segment: "all" } });

  assert.equal(result.status, "found");
  assert.equal(result.product.history.some(({ marketDate }) => marketDate === "2026-08-11"), false);
});

test("normalizes invalid D1 numeric fields to null across all observation readers", async () => {
  const rows = [{ ...observation("2026-08-13", categories[0], 1), price: "20.50", rating: "4.5", reviews: "100" }, { ...observation("2026-08-13", categories[0], 2), price: -1, rating: 9, reviews: 1.5 }, { ...observation("2026-08-13", categories[0], 3), price: "", rating: "Infinity", reviews: -2 }];
  const store = createD1DashboardStore({ prepare() { return { bind() { return this; }, async all() { return { results: rows }; } }; } });

  for (const result of [await store.listObservations(), await store.listCategoryObservations("2026-08-13", "pressure_washers"), await store.listProductHistory(rows[0].asin)]) {
    assert.deepEqual(result.map(({ price, rating, reviews }) => ({ price, rating, reviews })), [
      { price: 20.5, rating: 4.5, reviews: 100 },
      { price: null, rating: null, reviews: null },
      { price: null, rating: null, reviews: null },
    ]);
  }
});

test("reads product metadata through bound ASIN placeholders and treats malformed evidence as empty", async () => {
  const prepared = [];
  const bindings = [];
  const rows = [{
    marketplace: "AMAZON_US",
    asin: "B000000001",
    product_type: "electric_pressure_washer",
    classification_confidence: "high",
    classification_rule_id: "pressure-washer-v1",
    classification_rule_version: "1",
    classification_evidence_json: "not json",
    raw_brand: "Example",
    normalized_brand: "Example",
    normalized_brand_key: "example",
    brand_alias_rule_id: null,
    brand_source: "verified_metadata",
    first_seen_market_date: "2026-08-13",
    last_seen_market_date: "2026-08-13",
  }];
  const store = createD1DashboardStore({ prepare(sql) {
    prepared.push(sql);
    return {
      bind(...values) { bindings.push(values); return this; },
      async all() { return { results: rows }; },
    };
  } });

  assert.deepEqual(await store.listProductMetadataByAsins([]), []);
  const expected = [{
    marketplace: "AMAZON_US",
    asin: "B000000001",
    productType: "electric_pressure_washer",
    classificationConfidence: "high",
    classificationRuleId: "pressure-washer-v1",
    classificationRuleVersion: "1",
    classificationEvidence: [],
    rawBrand: "Example",
    normalizedBrand: "Example",
    normalizedBrandKey: "example",
    brandAliasRuleId: null,
    brandSource: "verified_metadata",
    firstSeenMarketDate: "2026-08-13",
    lastSeenMarketDate: "2026-08-13",
  }];
  assert.deepEqual(await store.listProductMetadata(), expected);
  assert.deepEqual(await store.listProductMetadataByAsins(["B000000001", "B000000002"]), expected);
  assert.match(prepared[1], /WHERE asin IN \(\?, \?\)/);
  assert.deepEqual(bindings, [["B000000001", "B000000002"]]);
});

test("isolates duplicate ASIN product history to the requested market", async () => {
  const store = completeStore(["2026-08-12", "2026-08-13"]);
  const washer = await loadLiveProduct("PRE0000001", { store, context: { marketplace: "US", category: "pressure_washers", segment: "all" } });
  const accessories = await loadLiveProduct("PRE0000001", { store, context: { marketplace: "US", category: "pressure_washer_accessories", segment: "all" } });

  assert.equal(washer.status, "found");
  assert.equal(washer.product.history.length, 2);
  assert.equal(washer.product.daysListed, 2);
  assert.equal(washer.product.category.key, "pressure_washers");
  assert.equal(accessories.status, "found");
  assert.equal(accessories.product.history.length, 2);
  assert.equal(accessories.product.category.key, "pressure_washer_accessories");
});

test("loads an explicitly requested valid market day without changing the raw history", async () => {
  const store = completeStore(["2026-08-12", "2026-08-13"]);
  const data = await loadLiveDashboard({ store, marketDate: "2026-08-12" });

  assert.equal(data.latestSnapshotDate, "2026-08-13");
  assert.equal(data.categoryRows.every((row) => row.marketDate === "2026-08-12"), true);
  assert.equal(data.categoryRows.every((row) => row.history.length === 1), true);
});

test("rejects a product detail outside the requested analytical segment", async () => {
  const store = completeStore(["2026-08-13"]);
  const result = await loadLiveProduct("PRE0000001", { store, context: { marketplace: "US", category: "pressure_washer_accessories", segment: "surface_cleaners" } });

  assert.deepEqual(result, { status: "not_found" });
});

test("limits product detail history to the requested valid market date", async () => {
  const store = completeStore(["2026-08-12", "2026-08-13"]);
  const result = await loadLiveProduct("PRE0000001", {
    store,
    marketDate: "2026-08-12",
    context: { marketplace: "US", category: "pressure_washers", segment: "all" },
  });

  assert.equal(result.status, "found");
  assert.deepEqual(result.product.history.map(({ marketDate }) => marketDate), ["2026-08-12"]);
});
