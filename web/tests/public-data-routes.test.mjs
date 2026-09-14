import assert from "node:assert/strict";
import { register } from "node:module";
import test from "node:test";
import { categories } from "../lib/catalog.ts";
import { parseCategoryRegistry, productionCategoryRegistry } from "../lib/category-registry.ts";
import { createMarketContextResolver, resolvePublicMarketQuery } from "../lib/market-context.ts";

const workerEnvironment = globalThis.__dashboardWorkerEnvironment ??= {};
register(`data:text/javascript,export async function resolve(specifier, context, nextResolve) { if (specifier === "cloudflare:workers") return { url: "data:text/javascript,export const env = globalThis.__dashboardWorkerEnvironment", shortCircuit: true }; return nextResolve(specifier, context); }`, import.meta.url);

function dynamicD1Environment(marketDate, {
  strictRankingQuery = false,
  dates: suppliedDates,
  incompleteCategoryDays = [],
  missingCategoryDays = [],
  observationRowCounts = {},
  productMetadata: suppliedProductMetadata,
  reportRows = [],
} = {}) {
  const dates = suppliedDates ?? ["2026-08-12", marketDate];
  const snapshots = dates.map((market_date) => ({ market_date, observed_at: `${market_date}T09:00:00Z`, complete_category_count: 3 }));
  const incomplete = new Set(incompleteCategoryDays);
  const missing = new Set(missingCategoryDays);
  const observationCountFor = (date, category) => observationRowCounts[`${date}:${category}`] ?? 30;
  const categoryDays = dates.flatMap((market_date) => categories.map((category) => ({
    market_date,
    category_key: category.key,
    observation_count: observationCountFor(market_date, category.key),
    complete: incomplete.has(`${market_date}:${category.key}`) ? 0 : 1,
    missing_ranks_json: "[]",
  }))).filter((day) => !missing.has(`${day.market_date}:${day.category_key}`));
  const observations = dates.flatMap((market_date) => categories.flatMap((category) => Array.from({ length: observationCountFor(market_date, category.key) }, (_, index) => {
    const rank = index + 1;
    const asin = category.key === "pressure_washers" && rank === (market_date === marketDate ? 4 : 12)
      ? "B123456789"
      : `${category.key.slice(0, 3).toUpperCase()}${String(rank).padStart(7, "0")}`;
    return { market_date, category_key: category.key, rank, asin, title: `${category.short} ${rank}`, url: `https://www.amazon.com/dp/${asin}`, price: 20, rating: 4.5, reviews: 100 };
  })));
  const latestPressureWashers = observations.filter((row) => row.market_date === marketDate && row.category_key === "pressure_washers");
  const productMetadata = suppliedProductMetadata ?? latestPressureWashers.slice(0, 5).map((row, index) => ({
    marketplace: "AMAZON_US",
    asin: row.asin,
    product_type: ["electric_pressure_washer", "gas_pressure_washer", "cordless_pressure_washer", "surface_cleaner", "unknown"][index],
    classification_confidence: index === 4 ? "low" : "high",
    classification_rule_id: index === 4 ? null : `rule-${index + 1}`,
    classification_rule_version: "product-rules-v1",
    classification_evidence_json: index === 4 ? '["NO_SAFE_RULE_MATCH"]' : `["rule-${index + 1}"]`,
    raw_brand: null,
    normalized_brand: null,
    normalized_brand_key: null,
    brand_alias_rule_id: null,
    brand_source: "unknown",
    first_seen_market_date: marketDate,
    last_seen_market_date: marketDate,
  }));
  const DB = {
    prepareCalls: 0,
      categoryObservationRequests: [],
      prepare(sql) {
        this.prepareCalls += 1;
        let values = [];
        return {
          bind(...bound) { values = bound; return this; },
          async first() { return null; },
          async all() {
            if (sql.includes("FROM reports")) return { results: reportRows.filter((row) => row.category_key === values[0]) };
            if (sql.includes("FROM snapshots")) return { results: snapshots };
            if (sql.includes("FROM category_days")) return { results: categoryDays };
            if (sql.includes("FROM product_metadata")) return { results: productMetadata };
            if (sql.includes("WHERE o.asin")) return { results: observations.filter((row) => row.asin === values[0]) };
            if (strictRankingQuery && sql.includes("FROM observations")) {
              if (sql.includes("market_date = ?") && sql.includes("category_key = ?")) {
                DB.categoryObservationRequests.push([...values]);
                return { results: observations.filter((row) => row.market_date === values[0] && row.category_key === values[1]) };
              }
              return { results: observations };
            }
            if (sql.includes("FROM observations")) {
              if (sql.includes("market_date = ?") && sql.includes("category_key = ?")) DB.categoryObservationRequests.push([...values]);
              return { results: sql.includes("market_date = ?") && sql.includes("category_key = ?")
                ? observations.filter((row) => row.market_date === values[0] && row.category_key === values[1])
                : observations };
            }
            return { results: [] };
          },
        };
      },
      async batch() { return []; },
    };
  return {
    DB,
    ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) },
  };
}

async function request(path, env = {}) {
  for (const key of Reflect.ownKeys(workerEnvironment)) delete workerEnvironment[key];
  Object.assign(workerEnvironment, env);
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}-${Math.random()}`);
  const { default: worker } = await import(workerUrl.href);
  return worker.fetch(
    new Request(`http://localhost${path}`, { headers: { accept: "application/json" } }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) }, ...env },
    { waitUntil() {}, passThroughOnException() {} },
  );
}

test("public market query validation accepts an injected Test Category and fails closed", () => {
  const fixture = structuredClone(productionCategoryRegistry);
  fixture.categories.push({
    categoryKey: "test_category", slug: "test-category", labelZh: "测试榜单", labelEn: "Test Category",
    nodeId: "999000111", sourceUrl: "https://www.amazon.com/Best-Sellers-Test/zgbs/test/999000111",
    targetCount: 30, enabled: true, reportFileToken: "Test_Category",
    segments: [{ key: "all", labelZh: "全部榜单", productTypes: [] }],
    defaults: Object.fromEntries(["overview", "market", "products", "brands", "rankings", "reports", "alerts", "data_status", "product_detail"].map((page) => [page, "all"])),
  });
  const resolver = createMarketContextResolver(parseCategoryRegistry(fixture));
  assert.deepEqual(resolvePublicMarketQuery({ marketplace: "US", category: "test_category", segment: "all" }, resolver), {
    ok: true,
    context: { marketplace: "US", category: "test_category", segment: "all" },
  });
  assert.deepEqual(resolvePublicMarketQuery({ marketplace: "US", category: "missing", segment: "all" }, resolver), {
    ok: false,
    error: "unsupported_market_context",
  });
});

test("public routes expose the same latest market day without internal details", async () => {
  const env = dynamicD1Environment("2026-08-13");
  for (const path of [
    "/api/public/overview",
    "/api/public/rankings?category=pressure_washers",
    "/api/public/products/B123456789",
  ]) {
    const response = await request(path, env);
    assert.equal(response.status, 200, path);
    const body = await response.text();
    assert.match(body, /2026-08-13/, path);
    assert.doesNotMatch(body, /746254487|C:\\Users|SYNC_SECRET|password|stack/i, path);
  }
});

test("reports validates and isolates the requested page-local market", async () => {
  const rows = [
    { key: "daily/2026-08-13/pressure_washers.pdf", market_date: "2026-08-13", category_key: "pressure_washers", kind: "daily", title: "PW", byte_count: 100 },
    { key: "daily/2026-08-13/sump_pumps.pdf", market_date: "2026-08-13", category_key: "sump_pumps", kind: "daily", title: "Sump", byte_count: 100 },
  ];
  const env = dynamicD1Environment("2026-08-13", { reportRows: rows });
  const response = await request("/api/public/reports?category=sump_pumps&segment=all", env);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.deepEqual(body.reports.map(({ category_key }) => category_key), ["sump_pumps"]);

  const invalid = await request("/api/public/reports?category=sump_pumps&segment=machines", env);
  assert.equal(invalid.status, 400);
});

test("public product route returns not_found when healthy D1 has no ASIN", async () => {
  const response = await request("/api/public/products/B000000000", dynamicD1Environment("2026-08-13"));
  assert.equal(response.status, 404);
  assert.deepEqual(await response.json(), { error: "not_found" });
});

test("public product route keeps the fallback source internal and shortens its cache", async () => {
  const live = await request("/api/public/products/B123456789", dynamicD1Environment("2026-08-13"));
  assert.equal(live.headers.get("cache-control"), "public, max-age=300");
  assert.doesNotMatch(await live.text(), /"source"/);

  const fallback = await request("/api/public/products/B0BVGSX46M");
  assert.equal(fallback.status, 200);
  assert.equal(fallback.headers.get("cache-control"), "public, max-age=60");
  assert.doesNotMatch(await fallback.text(), /"source"/);
});

test("fallback rankings retain the baseline comparison contract", async () => {
  const response = await request("/api/public/rankings?category=pressure_washers");
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.comparison.baselineDate, "2026-08-11");
  assert.equal(typeof body.comparison.ready, "boolean");
});

test("raw rankings keep all Top 30 rows when an analytical segment is requested", async () => {
  const response = await request(
    "/api/public/rankings?marketplace=US&category=pressure_washers&segment=machines",
    dynamicD1Environment("2026-08-13"),
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.observations.length, 30);
  assert.equal(body.scope, "raw_ranking");
});

test("overview returns a separately filtered analytical market", async () => {
  const response = await request(
    "/api/public/overview?marketplace=US&category=pressure_washers&segment=machines",
    dynamicD1Environment("2026-08-13"),
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.deepEqual(body.marketContext, { marketplace: "US", category: "pressure_washers", segment: "machines" });
  assert.equal(body.rawObservationCount, 30);
  assert.deepEqual(
    body.analyticalObservations.map(({ productType }) => productType),
    ["electric_pressure_washer", "gas_pressure_washer", "cordless_pressure_washer"],
  );
});

test("overview honors an explicitly requested valid market day", async () => {
  const response = await request(
    "/api/public/overview?marketplace=US&category=pressure_washers&segment=machines&date=2026-08-12",
    dynamicD1Environment("2026-08-13", { strictRankingQuery: true }),
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.marketDate, "2026-08-12");
  assert.equal(body.categoryRows.find(({ key }) => key === "pressure_washers").marketDate, "2026-08-12");
});

test("live analysis uses the requested analytical segment instead of the raw category", async () => {
  const env = dynamicD1Environment("2026-08-13");
  const machines = await request(
    "/api/public/analysis/live?kind=daily&category=pressure_washers&segment=machines",
    env,
  );
  assert.equal(machines.status, 200);
  assert.equal((await machines.json()).evidence.sampleSize, 3);

  const raw = await request(
    "/api/public/analysis/live?kind=daily&category=pressure_washers&segment=all_bestsellers",
    env,
  );
  assert.equal(raw.status, 200);
  assert.equal((await raw.json()).evidence.sampleSize, 30);
});

test("overview keeps metadata-missing rows only in all_bestsellers", async () => {
  const env = dynamicD1Environment("2026-08-13");
  const allResponse = await request(
    "/api/public/overview?marketplace=US&category=pressure_washers&segment=all_bestsellers",
    env,
  );
  assert.equal(allResponse.status, 200);
  const allBody = await allResponse.json();
  assert.equal(allBody.analyticalObservations.length, 30);
  assert.ok(allBody.analyticalObservations.some(({ productType }) => productType === "unknown"));

  const machineResponse = await request(
    "/api/public/overview?marketplace=US&category=pressure_washers&segment=machines",
    env,
  );
  assert.equal(machineResponse.status, 200);
  const machineBody = await machineResponse.json();
  assert.equal(machineBody.analyticalObservations.length, 3);
  assert.ok(machineBody.analyticalObservations.every(({ productType }) => productType !== "unknown"));
});

test("public market routes reject unsupported contexts without falling back", async () => {
  for (const path of [
    "/api/public/rankings?marketplace=US&category=sump_pumps&segment=machines",
    "/api/public/overview?marketplace=EU&category=pressure_washers&segment=machines",
  ]) {
    const env = dynamicD1Environment("2026-08-13");
    const response = await request(path, env);
    assert.equal(response.status, 400, path);
    assert.deepEqual(await response.json(), { error: "unsupported_market_context" }, path);
    assert.equal(env.DB.prepareCalls, 0, path);
  }
});

test("overview reports D1 failure instead of publishing seed data as analytical output", async () => {
  const response = await request("/api/public/overview?marketplace=US&category=pressure_washers&segment=machines");
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: "unavailable" });
});

async function assertOverviewFallsBackToPreviousValidDay(env) {
  const response = await request(
    "/api/public/overview?marketplace=US&category=pressure_washers&segment=machines",
    env,
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.marketDate, "2026-08-12");
  assert.equal(body.categoryRows.find(({ key }) => key === "pressure_washers").marketDate, "2026-08-12");
  assert.equal(body.analyticalObservations.length, 3);
}

test("overview excludes a persisted-incomplete latest day and falls back to the previous valid day", async () => {
  await assertOverviewFallsBackToPreviousValidDay(dynamicD1Environment("2026-08-13", {
    incompleteCategoryDays: ["2026-08-13:pressure_washers"],
  }));
});

test("overview excludes a latest day with only 29 actual rows", async () => {
  await assertOverviewFallsBackToPreviousValidDay(dynamicD1Environment("2026-08-13", {
    observationRowCounts: { "2026-08-13:pressure_washers": 29 },
  }));
});

test("overview excludes a latest day with no selected category-day record", async () => {
  await assertOverviewFallsBackToPreviousValidDay(dynamicD1Environment("2026-08-13", {
    missingCategoryDays: ["2026-08-13:pressure_washers"],
  }));
});

test("rankings validates market context and does not fabricate an unavailable requested date", async () => {
  const env = dynamicD1Environment("2026-08-13");
  const invalidCategory = await request("/api/public/rankings?category=unknown", env);
  assert.equal(invalidCategory.status, 400);
  assert.deepEqual(await invalidCategory.json(), { error: "unsupported_market_context" });

  const invalidDate = await request("/api/public/rankings?date=tomorrow", env);
  assert.equal(invalidDate.status, 400);
  assert.deepEqual(await invalidDate.json(), { error: "invalid_date" });

  const impossibleDate = await request("/api/public/rankings?date=2026-99-99", env);
  assert.equal(impossibleDate.status, 400);
  assert.deepEqual(await impossibleDate.json(), { error: "invalid_date" });

  const missingDate = await request("/api/public/rankings?category=pressure_washers&date=2026-08-14", env);
  assert.equal(missingDate.status, 404);
  assert.deepEqual(await missingDate.json(), { error: "not_found" });

  const unavailableDate = await request("/api/public/rankings?date=2026-08-13");
  assert.equal(unavailableDate.status, 503);
  assert.deepEqual(await unavailableDate.json(), { error: "unavailable" });
});

test("rankings uses a parameterized store query for an explicitly requested market day", async () => {
  const response = await request(
    "/api/public/rankings?category=pressure_washers&date=2026-08-12",
    dynamicD1Environment("2026-08-13", { strictRankingQuery: true }),
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.marketDate, "2026-08-12");
  assert.equal(body.observations.length, 30);
  assert.equal(body.quality.complete, true);
  assert.equal(body.comparison.baselineDate, null);
});

test("rankings compares an explicitly requested day with its immediately preceding complete day", async () => {
  const response = await request(
    "/api/public/rankings?category=pressure_washers&date=2026-08-13",
    dynamicD1Environment("2026-08-13", { strictRankingQuery: true }),
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.comparison.ready, true);
  assert.equal(body.comparison.baselineDate, "2026-08-12");
  const moved = body.comparison.movers.find(({ asin }) => asin === "B123456789");
  assert.equal(moved.previousRank, 12);
  assert.equal(moved.rank, 4);
  assert.equal(moved.change, 8);
});

test("rankings compares with the previous valid day across an incomplete snapshot", async () => {
  const env = dynamicD1Environment("2026-08-13", {
    strictRankingQuery: true,
    dates: ["2026-08-11", "2026-08-12", "2026-08-13"],
    incompleteCategoryDays: ["2026-08-12:pressure_washers"],
  });
  const response = await request("/api/public/rankings?category=pressure_washers&date=2026-08-13", env);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.comparison.ready, true);
  assert.equal(body.comparison.baselineDate, "2026-08-11");
  assert.ok(env.DB.categoryObservationRequests.some(([date, category]) => date === "2026-08-11" && category === "pressure_washers"));
});

test("rankings returns not_found when an explicit date lacks the selected category-day record", async () => {
  const response = await request(
    "/api/public/rankings?marketplace=US&category=pressure_washers&segment=machines&date=2026-08-13",
    dynamicD1Environment("2026-08-13", { missingCategoryDays: ["2026-08-13:pressure_washers"] }),
  );
  assert.equal(response.status, 404);
  assert.deepEqual(await response.json(), { error: "not_found" });
});

test("latest raw rankings distinguish a missing category day from collected partial and empty days", async () => {
  const missing = await request(
    "/api/public/rankings?marketplace=US&category=pressure_washers&segment=machines",
    dynamicD1Environment("2026-08-13", { missingCategoryDays: ["2026-08-13:pressure_washers"] }),
  );
  assert.equal(missing.status, 503);
  assert.deepEqual(await missing.json(), { error: "unavailable" });

  const partial = await request(
    "/api/public/rankings?marketplace=US&category=pressure_washers&segment=machines",
    dynamicD1Environment("2026-08-13", { incompleteCategoryDays: ["2026-08-13:pressure_washers"] }),
  );
  assert.equal(partial.status, 200);
  const partialBody = await partial.json();
  assert.equal(partialBody.observations.length, 30);
  assert.equal(partialBody.quality.complete, false);
  assert.equal(partialBody.scope, "raw_ranking");

  const empty = await request(
    "/api/public/rankings?marketplace=US&category=pressure_washers&segment=machines",
    dynamicD1Environment("2026-08-13", {
      incompleteCategoryDays: ["2026-08-13:pressure_washers"],
      observationRowCounts: { "2026-08-13:pressure_washers": 0 },
    }),
  );
  assert.equal(empty.status, 200);
  const emptyBody = await empty.json();
  assert.equal(emptyBody.observations.length, 0);
  assert.equal(emptyBody.quality.complete, false);
  assert.equal(emptyBody.scope, "raw_ranking");
});

test("product route rejects malformed ASINs without querying D1", async () => {
  const env = dynamicD1Environment("2026-08-13");
  const response = await request("/api/public/products/not-an-asin", env);
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_asin" });
  assert.equal(env.DB.prepareCalls, 0);
});
