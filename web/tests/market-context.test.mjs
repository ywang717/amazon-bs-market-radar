import assert from "node:assert/strict";
import test from "node:test";
import {
  MARKET_CONFIG,
  createMarketContextResolver,
  marketContextCacheKey,
  productTypeFiltersForContext,
  PAGE_MARKET_DEFAULTS,
  filterAnalyticalMarket,
  parseMarketContext,
  resolvePageMarketContext,
  resolveMarketDate,
  serializeMarketContext,
  validateMarketContext,
} from "../lib/market-context.ts";
import { parseCategoryRegistry, productionCategoryRegistry } from "../lib/category-registry.ts";

function registryWithTestCategory() {
  const fixture = structuredClone(productionCategoryRegistry);
  fixture.categories.push({
    categoryKey: "test_category",
    slug: "test-category",
    labelZh: "测试榜单",
    labelEn: "Test Category",
    nodeId: "999000111",
    sourceUrl: "https://www.amazon.com/Best-Sellers-Test/zgbs/test/999000111",
    targetCount: 30,
    enabled: true,
    reportFileToken: "Test_Category",
    segments: [{ key: "all", labelZh: "全部榜单", productTypes: [] }],
    defaults: Object.fromEntries([
      "overview", "market", "products", "brands", "rankings", "reports", "alerts", "data_status", "product_detail",
    ].map((page) => [page, "all"])),
  });
  return parseCategoryRegistry(fixture);
}

test("an injected Registry resolves and filters a Test Category without production branches", () => {
  const resolver = createMarketContextResolver(registryWithTestCategory());
  assert.deepEqual(
    resolver.resolvePageMarketContext("products", { category: "test_category", segment: "all" }).context,
    { marketplace: "US", category: "test_category", segment: "all" },
  );
  const rows = [{ asin: "TEST000001" }];
  assert.deepEqual(resolver.filterAnalyticalMarket(rows, [], {
    marketplace: "US", category: "test_category", segment: "all",
  }), rows);
  assert.deepEqual(resolver.validateMarketContext({ marketplace: "US", category: "missing", segment: "all" }), {
    ok: false, error: "unsupported_market_context",
  });
});

test("an injected Registry participates in every cache-key dimension", () => {
  const resolver = createMarketContextResolver(registryWithTestCategory());
  const keys = resolver.enabled.flatMap((category) => category.segments.flatMap((segment) => [
    resolver.marketContextCacheKey({ marketplace: "US", category: category.categoryKey, segment: segment.key }, { date: "2026-08-29", window: "7d" }),
    resolver.marketContextCacheKey({ marketplace: "US", category: category.categoryKey, segment: segment.key }, { date: "2026-08-29", window: "30d" }),
    resolver.marketContextCacheKey({ marketplace: "US", category: category.categoryKey, segment: segment.key }, { date: "2026-08-30", window: "7d" }),
    resolver.marketContextCacheKey({ marketplace: "US", category: category.categoryKey, segment: segment.key }, { date: "2026-08-30", window: "30d" }),
  ]));

  assert.equal(keys.length, 52);
  assert.equal(new Set(keys).size, 52);
  assert.ok(keys.includes("US:pressure_washers:machines:2026-08-29:7d"));
  assert.ok(keys.includes("US:test_category:all:2026-08-30:30d"));
});

test("uses an explicit valid market date and otherwise falls back to the latest valid day", () => {
  const validDates = ["2026-08-12", "2026-08-13", "2026-08-15"];
  assert.deepEqual(resolveMarketDate("2026-08-13", validDates), { marketDate: "2026-08-13", needsNormalization: false });
  assert.deepEqual(resolveMarketDate("2026-08-14", validDates), { marketDate: "2026-08-15", needsNormalization: true });
  assert.deepEqual(resolveMarketDate(undefined, validDates), { marketDate: "2026-08-15", needsNormalization: false });
});

test("isolates cached analysis by marketplace category segment date and window", () => {
  assert.equal(
    marketContextCacheKey({ marketplace: "US", category: "sump_pumps", segment: "all" }, { date: "2026-08-29", window: "7d" }),
    "US:sump_pumps:all:2026-08-29:7d",
  );
});

test("defaults to US pressure washers machines", () => {
  assert.deepEqual(parseMarketContext(new URL("https://example.test/")), {
    ok: true,
    context: { marketplace: "US", category: "pressure_washers", segment: "machines" },
  });
});

test("rejects an unsupported category segment combination", () => {
  assert.deepEqual(parseMarketContext(new URL("https://example.test/?marketplace=US&category=sump_pumps&segment=gas")), {
    ok: false,
    error: "unsupported_market_context",
  });
});

test("defines one authoritative config for all three Amazon nodes and their canonical segments", () => {
  assert.deepEqual(Object.fromEntries(Object.entries(MARKET_CONFIG).map(([key, value]) => [key, value.amazonNode])), {
    pressure_washers: "552856",
    sump_pumps: "680335011",
    pressure_washer_accessories: "3023451",
  });
  assert.deepEqual(MARKET_CONFIG.pressure_washers.segments.map(({ key }) => key), ["all", "machines", "electric", "gas", "cordless"]);
  assert.deepEqual(MARKET_CONFIG.pressure_washer_accessories.segments.map(({ key }) => key), ["all", "surface_cleaners", "guns", "hoses", "nozzles", "other"]);
});

test("uses page-specific defaults without scattering them through pages", () => {
  for (const page of ["overview", "market", "products", "brands", "reports", "alerts", "data_status"]) {
    assert.equal(PAGE_MARKET_DEFAULTS[page].pressure_washers, "machines", page);
    assert.equal(PAGE_MARKET_DEFAULTS[page].sump_pumps, "all", page);
    assert.equal(PAGE_MARKET_DEFAULTS[page].pressure_washer_accessories, "all", page);
  }
  assert.equal(PAGE_MARKET_DEFAULTS.rankings.pressure_washers, "all");
});

test("resolves explicit URL context and reports whether normalization is needed", () => {
  const explicit = resolvePageMarketContext("products", new URLSearchParams("category=sump_pumps&segment=all&query=pump"));
  assert.deepEqual(explicit.context, { marketplace: "US", category: "sump_pumps", segment: "all" });
  assert.equal(explicit.needsNormalization, false);
  assert.equal(explicit.searchParams.get("query"), "pump");

  const missing = resolvePageMarketContext("rankings", new URLSearchParams());
  assert.deepEqual(missing.context, { marketplace: "US", category: "pressure_washers", segment: "all" });
  assert.equal(missing.needsNormalization, false);
  assert.equal(missing.searchParams.toString(), "category=pressure_washers&segment=all");
});

test("normalizes unknown categories and resets invalid segments for the resolved category", () => {
  const unknown = resolvePageMarketContext("overview", new URLSearchParams("category=abc&segment=gas&view=movers"));
  assert.deepEqual(unknown.context, { marketplace: "US", category: "pressure_washers", segment: "machines" });
  assert.equal(unknown.searchParams.get("view"), "movers");

  const invalidPair = resolvePageMarketContext("market", new URLSearchParams("category=sump_pumps&segment=electric&window=7"));
  assert.deepEqual(invalidPair.context, { marketplace: "US", category: "sump_pumps", segment: "all" });
  assert.equal(invalidPair.searchParams.get("window"), "7");
  assert.equal(invalidPair.needsNormalization, true);
});

test("serializes context without dropping page-local query parameters", () => {
  assert.equal(
    serializeMarketContext(
      { marketplace: "US", category: "pressure_washer_accessories", segment: "hoses" },
      new URLSearchParams("view=price&window=30&date=2026-08-29&category=pressure_washers&segment=machines"),
    ),
    "view=price&window=30&date=2026-08-29&category=pressure_washer_accessories&segment=hoses",
  );
});

test("filters machines without changing raw rows", () => {
  const raw = [{ asin: "B000000001" }, { asin: "B000000002" }, { asin: "B000000003" }];
  const metadata = [
    { asin: "B000000001", productType: "electric_pressure_washer" },
    { asin: "B000000002", productType: "surface_cleaner" },
    { asin: "B000000003", productType: "unknown" },
  ];
  const result = filterAnalyticalMarket(raw, metadata, { marketplace: "US", category: "pressure_washers", segment: "machines" });
  assert.deepEqual(result.map(({ asin }) => asin), ["B000000001"]);
  assert.equal(raw.length, 3);
});

const pressureWasherRows = [
  { asin: "electric", productType: "electric_pressure_washer" },
  { asin: "gas", productType: "gas_pressure_washer" },
  { asin: "cordless", productType: "cordless_pressure_washer" },
  { asin: "surface", productType: "surface_cleaner" },
  { asin: "gun", productType: "pressure_washer_gun" },
  { asin: "hose", productType: "hose" },
  { asin: "nozzle", productType: "nozzle" },
  { asin: "chemical", productType: "chemical_cleaner" },
  { asin: "protector", productType: "pump_protector" },
  { asin: "other", productType: "other_accessory" },
  { asin: "unknown", productType: "unknown" },
];

const pressureWasherExpected = {
  all: pressureWasherRows.map(({ asin }) => asin),
  machines: ["electric", "gas", "cordless"],
  electric: ["electric"],
  gas: ["gas"],
  cordless: ["cordless"],
};

for (const [segment, expected] of Object.entries(pressureWasherExpected)) {
  test(`filters pressure washers ${segment}`, () => {
    const raw = pressureWasherRows.map(({ asin }) => ({ asin }));
    const original = raw.map((row) => ({ ...row }));
    const result = filterAnalyticalMarket(raw, pressureWasherRows, {
      marketplace: "US",
      category: "pressure_washers",
      segment,
    });
    assert.deepEqual(result.map(({ asin }) => asin), expected);
    assert.deepEqual(raw, original);
  });
}

test("sump pumps only supports all in V2.1", () => {
    assert.deepEqual(validateMarketContext({ marketplace: "US", category: "sump_pumps", segment: "all" }), {
      ok: true,
      context: { marketplace: "US", category: "sump_pumps", segment: "all" },
    });
    for (const segment of ["machines", "electric", "gas", "cordless", "surface_cleaners"]) {
      assert.deepEqual(validateMarketContext({ marketplace: "US", category: "sump_pumps", segment }), {
        ok: false,
        error: "unsupported_market_context",
      });
    }
});

test("exposes only reliable page-local product type filters", () => {
  assert.deepEqual(
    productTypeFiltersForContext({ marketplace: "US", category: "pressure_washers", segment: "machines" }).map(({ key }) => key),
    ["electric", "gas", "cordless"],
  );
  assert.deepEqual(
    productTypeFiltersForContext({ marketplace: "US", category: "pressure_washer_accessories", segment: "all" }).map(({ key }) => key),
    ["surface_cleaners", "guns", "hoses", "nozzles", "other"],
  );
  assert.deepEqual(productTypeFiltersForContext({ marketplace: "US", category: "sump_pumps", segment: "all" }), []);
});

const independentAccessoryExpected = {
  all: pressureWasherRows.map(({ asin }) => asin),
  surface_cleaners: ["surface"],
  guns: ["gun"],
  hoses: ["hose"],
  nozzles: ["nozzle"],
  other: ["chemical", "protector", "other"],
};

for (const [segment, expected] of Object.entries(independentAccessoryExpected)) {
  test(`filters the independent accessories market by ${segment}`, () => {
    const raw = pressureWasherRows.map(({ asin }) => ({ asin }));
    const result = filterAnalyticalMarket(raw, pressureWasherRows, {
      marketplace: "US",
      category: "pressure_washer_accessories",
      segment,
    });
    assert.deepEqual(result.map(({ asin }) => asin), expected);
  });
}

test("rejects unsupported marketplace, category, and segment values", () => {
  assert.deepEqual(validateMarketContext({ marketplace: "UK", category: "pressure_washers", segment: "machines" }), {
    ok: false,
    error: "unsupported_market_context",
  });
  assert.deepEqual(validateMarketContext({ marketplace: "US", category: "not_a_category", segment: "machines" }), {
    ok: false,
    error: "unsupported_market_context",
  });
  assert.deepEqual(validateMarketContext({ marketplace: "US", category: "pressure_washers", segment: "not_a_segment" }), {
    ok: false,
    error: "unsupported_market_context",
  });
});

test("all returns a shallow copy", () => {
  const raw = [{ asin: "B000000001" }];
  const result = filterAnalyticalMarket(raw, [], { marketplace: "US", category: "sump_pumps", segment: "all" });
  assert.deepEqual(result, raw);
  assert.notEqual(result, raw);
});
