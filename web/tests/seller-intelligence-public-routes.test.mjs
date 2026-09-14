import assert from "node:assert/strict";
import { register } from "node:module";
import test from "node:test";

const workerEnvironment = globalThis.__dashboardWorkerEnvironment ??= {};
const projectRootUrl = new URL("../", import.meta.url).href;
register(`data:text/javascript,const projectRootUrl=${JSON.stringify(projectRootUrl)};export async function resolve(specifier, context, nextResolve) { if (specifier === "cloudflare:workers") return { url: "data:text/javascript,export const env = globalThis.__dashboardWorkerEnvironment", shortCircuit: true }; if (specifier.startsWith("@/")) { const path = /\\.[a-z]+$/i.test(specifier) ? specifier.slice(2) : \`\${specifier.slice(2)}.ts\`; return { url: new URL(path, projectRootUrl).href, shortCircuit: true }; } return nextResolve(specifier, context); }`, import.meta.url);

async function loadSellerIntelligenceModule() {
  const url = new URL("../lib/seller-intelligence.ts", import.meta.url);
  url.searchParams.set("test", `${Date.now()}-${Math.random()}`);
  return import(url.href);
}

async function loadProductSpecsModule() {
  const url = new URL("../lib/product-specs.ts", import.meta.url);
  url.searchParams.set("test", `${Date.now()}-${Math.random()}`);
  return import(url.href);
}

async function importRoute(relativePath) {
  const url = new URL(relativePath, import.meta.url);
  url.searchParams.set("test", `${Date.now()}-${Math.random()}`);
  return import(url.href);
}

function observation(rank, overrides = {}) {
  return {
    rank,
    asin: `B${String(rank).padStart(9, "0")}`,
    title: `Pressure Washer ${rank}`,
    url: `https://www.amazon.com/dp/B${String(rank).padStart(9, "0")}`,
    price: 100 + rank,
    rating: 4.5,
    reviews: 100 + rank,
    has_discount: false,
    discounts: [],
    ...overrides,
  };
}

function row(key, label, observations, overrides = {}) {
  const presentPrice = observations.filter(({ price }) => price !== null).length;
  const presentRating = observations.filter(({ rating }) => rating !== null).length;
  const presentReviews = observations.filter(({ reviews }) => reviews !== null).length;
  return {
    key,
    label,
    quality: { complete: observations.length === 30 },
    observations,
    priceCoverage: { percent: observations.length === 0 ? 0 : Math.round((presentPrice / observations.length) * 1000) / 10 },
    ratingCoverage: { percent: observations.length === 0 ? 0 : Math.round((presentRating / observations.length) * 1000) / 10 },
    reviewsCoverage: { percent: observations.length === 0 ? 0 : Math.round((presentReviews / observations.length) * 1000) / 10 },
    comparison: {
      ready: false,
      reason: "需要相邻两个完整 Top 30 市场日",
      averageAbsoluteMove: null,
      maxAbsoluteMove: null,
      top10Retained: null,
      entries: null,
      exits: null,
      largeMoves: null,
      highPriorityMoves: null,
      movementBands: null,
      movers: [],
      baselineDate: null,
    },
    ...overrides,
  };
}

function dashboard({ completeMarketDays = 1, categoryRows } = {}) {
  return {
    marketDate: "2026-08-24",
    observedAt: "2026-08-25T01:00:00Z",
    completeMarketDays,
    evidence: completeMarketDays >= 5 ? "充分" : completeMarketDays >= 2 ? "可用" : "有限",
    categoryRows: categoryRows ?? [],
  };
}

function completeSellerAlertDashboard() {
  const previous = Array.from({ length: 30 }, (_, index) => observation(index + 1));
  const current = previous.map((item) => ({ ...item, title: "2000 PSI 1.8 GPM Electric Washer with 25 FT Hose" }));
  current[3] = { ...current[3], asin: previous[25].asin, title: previous[25].title, url: previous[25].url };
  current[25] = { ...current[25], asin: previous[3].asin, title: previous[3].title, url: previous[3].url };
  const comparisonMovers = [
    { ...current[3], previousRank: 26, change: 22, absoluteMove: 22 },
    { ...current[25], previousRank: 4, change: -22, absoluteMove: 22 },
  ];
  return dashboard({
    completeMarketDays: 2,
    categoryRows: [
      row("pressure_washers", "高压清洗机", current, {
        comparison: {
          ready: true,
          reason: null,
          averageAbsoluteMove: 1.5,
          maxAbsoluteMove: 22,
          top10Retained: 9,
          entries: 0,
          exits: 0,
          largeMoves: 2,
          highPriorityMoves: 2,
          movementBands: { stable: 28, moderate: 0, notable: 0, large: 2 },
          movers: comparisonMovers,
          baselineDate: "2026-08-23",
        },
      }),
      row("sump_pumps", "污水泵", Array.from({ length: 30 }, (_, index) => observation(index + 1, { asin: `S${String(index + 1).padStart(9, "0")}` }))),
      row("pressure_washer_accessories", "高压清洗机配件", Array.from({ length: 30 }, (_, index) => observation(index + 1, { asin: `A${String(index + 1).padStart(9, "0")}` }))),
    ],
  });
}

function incompleteDashboard() {
  return dashboard({
    completeMarketDays: 1,
    categoryRows: [
      row("pressure_washers", "高压清洗机", Array.from({ length: 30 }, (_, index) => observation(index + 1))),
      row("sump_pumps", "污水泵", Array.from({ length: 29 }, (_, index) => observation(index + 1, { asin: `S${String(index + 1).padStart(9, "0")}` })), {
        quality: { complete: false },
      }),
      row("pressure_washer_accessories", "高压清洗机配件", Array.from({ length: 30 }, (_, index) => observation(index + 1, { asin: `A${String(index + 1).padStart(9, "0")}` }))),
    ],
  });
}

function strategyDashboard(completeMarketDays) {
  const rows = [
    row("pressure_washers", "高压清洗机", Array.from({ length: 30 }, (_, index) => observation(index + 1))),
    row("sump_pumps", "污水泵", Array.from({ length: 30 }, (_, index) => observation(index + 1, { asin: `S${String(index + 1).padStart(9, "0")}` }))),
    row("pressure_washer_accessories", "高压清洗机配件", Array.from({ length: 30 }, (_, index) => observation(index + 1, { asin: `A${String(index + 1).padStart(9, "0")}` }))),
  ];
  return dashboard({ completeMarketDays, categoryRows: rows });
}

function lowCoverageStrategyDashboard() {
  const sparse = Array.from({ length: 30 }, (_, index) => observation(index + 1, index < 9 ? {} : {
    price: null,
    rating: null,
    reviews: null,
  }));
  return dashboard({
    completeMarketDays: 6,
    categoryRows: [
      row("pressure_washers", "高压清洗机", sparse),
      row("sump_pumps", "污水泵", Array.from({ length: 30 }, (_, index) => observation(index + 1, { asin: `S${String(index + 1).padStart(9, "0")}` }))),
      row("pressure_washer_accessories", "高压清洗机配件", Array.from({ length: 30 }, (_, index) => observation(index + 1, { asin: `A${String(index + 1).padStart(9, "0")}` }))),
    ],
  });
}

function archivedReport(overrides = {}) {
  return {
    schemaVersion: "seller-intelligence-v1",
    key: "seller-alert/daily/2026-08-24/pressure_washers.json",
    reportKind: "daily",
    profile: "seller_alert",
    marketDate: "2026-08-24",
    categoryKey: "pressure_washers",
    generatedAt: "2026-08-25T01:00:00Z",
    generatorVersion: "seller-rules-v1",
    contentSha256: "a".repeat(64),
    evidence: {
      complete: true,
      completeMarketDays: 6,
      sampleSize: 30,
      fieldCoverage: { price: 100, rating: 100, reviews: 100, discount: 100, specs: 0 },
    },
    signals: [
      {
        priority: "high",
        kind: "rank_move",
        asin: "B000000001",
        currentRank: 4,
        previousRank: 26,
        checks: ["核查价格与优惠状态"],
        evidence: ["排名由 #26 上升至 #4"],
      },
    ],
    sections: [{ title: "经营预警", statements: ["发现 1 个高优先级待核查变化。"] }],
    limitations: ["描述性观察，不代表销量或利润预测。"],
    ...overrides,
  };
}

function environment({ rows = [], reports = new Map(), dashboardData = completeSellerAlertDashboard(), throwOnList = false, throwOnLiveRead = false } = {}) {
  const statements = [];
  return {
    statements,
    ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) },
    DB: {
      prepare(sql) {
        let values = [];
        return {
          bind(...bound) {
            values = bound;
            return this;
          },
          async first() {
            if (sql.includes("FROM seller_intelligence_reports WHERE key = ?")) {
              const content = reports.get(values[0]);
              return content ? { content_json: content } : null;
            }
            return null;
          },
          async all() {
            statements.push({ sql, values });
            if (throwOnList && sql.includes("FROM seller_intelligence_reports")) throw new Error("D1 exploded C:\\Users\\ASUS\\secret");
            if (throwOnLiveRead && (sql.includes("FROM snapshots") || sql.includes("FROM category_days") || sql.includes("FROM observations"))) {
              throw new Error("dashboard backend failure C:\\Users\\ASUS\\secret");
            }
            if (sql.includes("FROM snapshots")) {
              return {
                results: [
                  { market_date: dashboardData.marketDate, observed_at: dashboardData.observedAt, complete_category_count: dashboardData.categoryRows.filter((entry) => entry.quality.complete).length },
                  ...Array.from({ length: Math.max(dashboardData.completeMarketDays - 1, 0) }, (_, index) => ({
                    market_date: `2026-08-${String(23 - index).padStart(2, "0")}`,
                    observed_at: `2026-08-${String(23 - index).padStart(2, "0")}T01:00:00Z`,
                    complete_category_count: dashboardData.categoryRows.length,
                  })),
                ],
              };
            }
            if (sql.includes("FROM category_days")) {
              return {
                results: [
                  ...dashboardData.categoryRows.map((entry) => ({
                    market_date: dashboardData.marketDate,
                    category_key: entry.key,
                    observation_count: entry.observations.length,
                    complete: entry.quality.complete ? 1 : 0,
                    missing_ranks_json: "[]",
                  })),
                  ...Array.from({ length: Math.max(dashboardData.completeMarketDays - 1, 0) }, (_, index) =>
                    dashboardData.categoryRows.map((entry) => ({
                      market_date: `2026-08-${String(23 - index).padStart(2, "0")}`,
                      category_key: entry.key,
                      observation_count: 30,
                      complete: 1,
                      missing_ranks_json: "[]",
                    })),
                  ).flat(),
                ],
              };
            }
            if (sql.includes("FROM observations")) {
              return {
                results: [
                  ...dashboardData.categoryRows.flatMap((entry) => entry.observations.map((item) => ({
                    market_date: dashboardData.marketDate,
                    category_key: entry.key,
                    rank: item.rank,
                    asin: item.asin,
                    title: item.title,
                    url: item.url,
                    price: item.price,
                    rating: item.rating,
                    reviews: item.reviews,
                    has_discount: item.has_discount === null ? null : item.has_discount ? 1 : 0,
                    discounts_json: JSON.stringify(item.discounts),
                  }))),
                  ...Array.from({ length: Math.max(dashboardData.completeMarketDays - 1, 0) }, (_, index) =>
                    dashboardData.categoryRows.flatMap((entry) =>
                      Array.from({ length: 30 }, (_, itemIndex) => {
                        const rank = itemIndex + 1;
                        const asin = `${entry.key.slice(0, 3).toUpperCase()}${String(rank).padStart(7, "0")}`;
                        return {
                          market_date: `2026-08-${String(23 - index).padStart(2, "0")}`,
                          category_key: entry.key,
                          rank,
                          asin,
                          title: `${entry.label} ${rank}`,
                          url: `https://www.amazon.com/dp/${asin}`,
                          price: 100 + rank,
                          rating: 4.5,
                          reviews: 100 + rank,
                          has_discount: 0,
                          discounts_json: "[]",
                        };
                      }),
                    ),
                  ).flat(),
                ],
              };
            }
            if (sql.includes("FROM seller_intelligence_reports")) {
              return { results: rows };
            }
            return { results: [] };
          },
        };
      },
      async batch(batch) {
        statements.push(...batch);
        return [];
      },
    },
  };
}

async function request(path, env = environment()) {
  for (const key of Reflect.ownKeys(workerEnvironment)) delete workerEnvironment[key];
  Object.assign(workerEnvironment, env);
  const requestUrl = new URL(`http://localhost${path}`);
  const pathname = requestUrl.pathname;
  if (pathname === "/api/public/seller-intelligence") {
    const { GET } = await importRoute("../app/api/public/seller-intelligence/route.ts");
    return GET(new Request(requestUrl, { headers: { accept: "application/json" } }));
  }
  if (pathname === "/api/public/seller-intelligence/live") {
    const { GET } = await importRoute("../app/api/public/seller-intelligence/live/route.ts");
    return GET(new Request(requestUrl, { headers: { accept: "application/json" } }));
  }
  if (pathname.startsWith("/api/public/seller-intelligence/")) {
    const { GET } = await importRoute("../app/api/public/seller-intelligence/[...key]/route.ts");
    const parts = pathname.replace("/api/public/seller-intelligence/", "").split("/");
    return GET(new Request(requestUrl, { headers: { accept: "application/json" } }), { params: Promise.resolve({ key: parts }) });
  }
  throw new Error(`Unsupported test route: ${path}`);
}

test("suppresses signals for an incomplete category", async () => {
  const { buildLiveSellerIntelligence } = await loadSellerIntelligenceModule();
  const report = await buildLiveSellerIntelligence(incompleteDashboard(), {
    profile: "seller_alert",
    categoryKey: "sump_pumps",
  });

  assert.equal(report.signals.length, 0);
  assert.match(report.sections.flatMap((section) => section.statements).join(" "), /暂不下结论/);
});

test("emits a high alert only for two complete comparison days", async () => {
  const { buildLiveSellerIntelligence } = await loadSellerIntelligenceModule();
  const report = await buildLiveSellerIntelligence(completeSellerAlertDashboard(), {
    profile: "seller_alert",
    categoryKey: "pressure_washers",
  });

  assert.equal(report.signals[0].priority, "high");
  assert.equal(report.signals[0].currentRank, 4);
  assert.equal(report.signals[0].previousRank, 26);
});

test("emits complete Top 30 entry exit and verifiable discount evidence from the adjacent market day", async () => {
  const { buildLiveSellerIntelligence } = await loadSellerIntelligenceModule();
  const previous = Array.from({ length: 30 }, (_, index) => observation(index + 1));
  const current = previous.map((item) => ({ ...item, title: "2000 PSI 1.8 GPM Electric Washer with 25 FT Hose" }));
  current[0] = { ...current[0], has_discount: true, discounts: [{ kind: "COUPON", amount: "10% off" }] };
  current[29] = observation(30, { asin: "B000000999", title: "2000 PSI 1.8 GPM Electric Washer with 25 FT Hose" });
  const currentByAsin = new Map(current.map((item) => [item.asin, item]));
  const report = await buildLiveSellerIntelligence(dashboard({
    completeMarketDays: 2,
    categoryRows: [
      row("pressure_washers", "高压清洗机", current, {
        comparison: {
          ...row("pressure_washers", "高压清洗机", current).comparison,
          ready: true,
          baselineDate: "2026-08-23",
          movers: current.filter((item) => item.asin !== "B000000999").map((item) => ({ ...item, previousRank: item.rank, absoluteMove: 0 })),
        },
        previousObservations: previous,
      }),
    ],
  }), { profile: "seller_alert", categoryKey: "pressure_washers" });

  const entry = report.signals.find((signal) => signal.kind === "new_entry");
  const exit = report.signals.find((signal) => signal.kind === "exit");
  const discount = report.signals.find((signal) => signal.kind === "discount_change");
  assert.deepEqual([entry?.currentRank, entry?.previousRank], [30, null]);
  assert.deepEqual([exit?.currentRank, exit?.previousRank], [null, 30]);
  assert.equal(discount?.discountBefore, "none");
  assert.equal(discount?.discountAfter, "COUPON:10% off");
  assert.equal(report.evidence.fieldCoverage.specs, 100);
  assert.equal(currentByAsin.has(entry?.asin ?? ""), true);
});

test("keeps competition strategy in a quality-disclosure state below five complete days", async () => {
  const { buildLiveSellerIntelligence } = await loadSellerIntelligenceModule();
  const report = await buildLiveSellerIntelligence(strategyDashboard(4), {
    profile: "competition_strategy",
    categoryKey: "pressure_washers",
  });

  assert.equal(report.signals.length, 0);
  assert.match(report.sections.flatMap((section) => section.statements).join(" "), /数据积累中，暂不输出稳定趋势|暂不下结论/);
});

test("pauses competition strategy disclosures when field coverage is below eighty percent", async () => {
  const { buildLiveSellerIntelligence } = await loadSellerIntelligenceModule();
  const report = await buildLiveSellerIntelligence(lowCoverageStrategyDashboard(), {
    profile: "competition_strategy",
    categoryKey: "pressure_washers",
  });

  assert.equal(report.strategy?.priceBands, null);
  assert.equal(report.strategy?.specificationTrend, null);
});

test("returns structured gated strategy facts instead of interchangeable narrative cards", async () => {
  const { buildLiveSellerIntelligence } = await loadSellerIntelligenceModule();
  const categoryRows = strategyDashboard(5).categoryRows;
  const focus = {
    ...categoryRows[0],
    observations: categoryRows[0].observations.map((item) => ({ ...item, title: "2000 PSI 1.8 GPM Electric Washer with 25 FT Hose" })),
    comparison: { ...categoryRows[0].comparison, ready: true, baselineDate: "2026-08-23", top10Retained: 9, entries: 1, exits: 1 },
  };
  const history = Array.from({ length: 5 }, (_, day) => ({
    marketDate: `2026-08-${String(20 + day).padStart(2, "0")}`,
    observations: focus.observations.map((item) => ({ ...item, title: "2000 PSI 1.8 GPM Electric Washer with 25 FT Hose" })),
  }));
  const report = await buildLiveSellerIntelligence(dashboard({
    completeMarketDays: 5,
    categoryRows: [{ ...focus, completeMarketDays: 5, history }],
  }), { profile: "competition_strategy", categoryKey: "pressure_washers" });

  assert.ok(report.strategy);
  assert.ok(report.strategy.priceBands?.length);
  assert.ok(report.strategy.rankingConcentration);
  assert.ok(report.strategy.topStability);
  assert.ok(report.strategy.competitorPool?.length);
  assert.deepEqual(report.strategy.specificationTrend?.observedFields.sort(), ["工作压力", "流量", "动力类型", "软管长度"].sort());
});

test("archive list query binds profile category and date filters", async () => {
  const env = environment();
  const response = await request("/api/public/seller-intelligence?profile=seller_alert&category=pressure_washers&date=2026-08-24", env);
  assert.equal(response.status, 200);

  const archiveQuery = env.statements.find(({ sql }) => sql.includes("FROM seller_intelligence_reports"));
  assert.ok(archiveQuery);
  assert.match(archiveQuery.sql, /WHERE profile = \? AND category_key = \? AND market_date = \?/);
  assert.deepEqual(archiveQuery.values, ["seller_alert", "pressure_washers", "2026-08-24"]);
});

test("reads only explicit product specifications from the title", async () => {
  const { readExplicitSpecifications } = await loadProductSpecsModule();

  assert.deepEqual(readExplicitSpecifications("Compact Washer for Patio Cleaning"), []);
  assert.deepEqual(
    readExplicitSpecifications("1800 PSI Degasser Electric Washer with 50 FT CORD"),
    [
      { label: "工作压力", value: "1800 PSI" },
      { label: "动力类型", value: "电动" },
      { label: "电源线长度", value: "50 FT" },
    ],
  );
  assert.deepEqual(
    readExplicitSpecifications("2200 PSI Washer with 50 FT Cover"),
    [{ label: "工作压力", value: "2200 PSI" }],
  );
  assert.deepEqual(
    readExplicitSpecifications("2000 PSI Electric Washer with 50 FT CORD WITH 25 FT HOSE"),
    [
      { label: "工作压力", value: "2000 PSI" },
      { label: "动力类型", value: "电动" },
      { label: "软管长度", value: "25 FT" },
      { label: "电源线长度", value: "50 FT" },
    ],
  );
  assert.deepEqual(
    readExplicitSpecifications("Electric Washer HOSE 25 FT with CORD 50 FT"),
    [
      { label: "动力类型", value: "电动" },
      { label: "软管长度", value: "25 FT" },
      { label: "电源线长度", value: "50 FT" },
    ],
  );
});

test("lists and reads only validated seller intelligence reports", async () => {
  const report = archivedReport();
  const env = environment({
    rows: [{
      key: report.key,
      report_kind: report.reportKind,
      profile: report.profile,
      market_date: report.marketDate,
      category_key: report.categoryKey,
      generated_at: report.generatedAt,
      generator_version: report.generatorVersion,
      content_sha256: report.contentSha256,
    }],
    reports: new Map([[report.key, JSON.stringify(report)]]),
  });

  const list = await request("/api/public/seller-intelligence?profile=seller_alert&category=pressure_washers&date=2026-08-24", env);
  assert.equal(list.status, 200);
  const listText = await list.text();
  assert.match(listText, /seller-alert\/daily\/2026-08-24\/pressure_washers\.json/);
  assert.doesNotMatch(listText, /C:\\Users|SMTP|secret|746254487/i);

  const detail = await request("/api/public/seller-intelligence/seller-alert/daily/2026-08-24/pressure_washers.json", env);
  assert.equal(detail.status, 200);
  assert.equal((await detail.json()).key, report.key);
});

test("omits archived metadata rows that fail safe public validation", async () => {
  const valid = archivedReport();
  const env = environment({
    rows: [
      {
        key: "seller-alert/daily/2026-08-24/overview.json",
        report_kind: "daily",
        profile: "seller_alert",
        market_date: "2026-08-24",
        category_key: null,
        generated_at: "2026-08-25T01:00:00Z",
        generator_version: "seller-rules-v1",
        content_sha256: "c".repeat(64),
      },
      {
        key: valid.key,
        report_kind: valid.reportKind,
        profile: valid.profile,
        market_date: valid.marketDate,
        category_key: valid.categoryKey,
        generated_at: valid.generatedAt,
        generator_version: valid.generatorVersion,
        content_sha256: valid.contentSha256,
      },
      {
        key: "seller-alert/daily/2026-08-24/pressure_washers.json",
        report_kind: "daily",
        profile: "seller_alert",
        market_date: "2026-08-24",
        category_key: "pressure_washers",
        generated_at: "C:\\Users\\ASUS\\secret",
        generator_version: "seller-rules-v1",
        content_sha256: "a".repeat(64),
      },
      {
        key: "seller-alert/daily/2026-08-24/overview.json",
        report_kind: "daily",
        profile: "seller_alert",
        market_date: "2026-08-24",
        category_key: "pressure_washers",
        generated_at: "2026-08-25T01:00:00Z",
        generator_version: "seller-rules-v1",
        content_sha256: "b".repeat(64),
      },
      {
        key: "seller-alert/daily/2026-08-24/pressure_washers.json",
        report_kind: "daily",
        profile: "seller_alert",
        market_date: "2026-08-24",
        category_key: null,
        generated_at: "2026-08-25T01:00:00Z",
        generator_version: "seller-rules-v1",
        content_sha256: "d".repeat(64),
      },
    ],
  });

  const response = await request("/api/public/seller-intelligence", env);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.reports.length, 2);
  assert.deepEqual(body.reports[0], {
    key: "seller-alert/daily/2026-08-24/overview.json",
    report_kind: "daily",
    profile: "seller_alert",
    market_date: "2026-08-24",
    category_key: null,
    generated_at: "2026-08-25T01:00:00Z",
    generator_version: "seller-rules-v1",
    content_sha256: "c".repeat(64),
  });
  assert.deepEqual(body.reports[1], {
    key: valid.key,
    report_kind: valid.reportKind,
    profile: valid.profile,
    market_date: valid.marketDate,
    category_key: valid.categoryKey,
    generated_at: valid.generatedAt,
    generator_version: valid.generatorVersion,
    content_sha256: valid.contentSha256,
  });
  assert.doesNotMatch(JSON.stringify(body), /C:\\Users|secret/i);
});

test("detail route revalidates stored JSON and hides invalid archived content", async () => {
  const response = await request(
    "/api/public/seller-intelligence/seller-alert/daily/2026-08-24/pressure_washers.json",
    environment({
      rows: [{
        key: "seller-alert/daily/2026-08-24/pressure_washers.json",
        report_kind: "daily",
        profile: "seller_alert",
        market_date: "2026-08-24",
        category_key: "pressure_washers",
        generated_at: "2026-08-25T01:00:00Z",
        generator_version: "seller-rules-v1",
        content_sha256: "a".repeat(64),
      }],
      reports: new Map([[
        "seller-alert/daily/2026-08-24/pressure_washers.json",
        JSON.stringify(archivedReport({
          signals: [{
            priority: "high",
            kind: "rank_move",
            asin: "B000000001",
            currentRank: 4,
            previousRank: 26,
            checks: ["database backup task failed after internal error"],
            evidence: ["排名由 #26 上升至 #4"],
          }],
        })),
      ]]),
    }),
  );

  assert.equal(response.status, 404);
  assert.deepEqual(await response.json(), { error: "not_found" });
});

test("list and live routes validate inputs and keep database failures private", async () => {
  const invalidProfile = await request("/api/public/seller-intelligence?profile=unknown", environment());
  assert.equal(invalidProfile.status, 400);
  assert.deepEqual(await invalidProfile.json(), { error: "invalid_profile" });

  const invalidDate = await request("/api/public/seller-intelligence?date=2026-99-99", environment());
  assert.equal(invalidDate.status, 400);
  assert.deepEqual(await invalidDate.json(), { error: "invalid_date" });

  const invalidCategory = await request("/api/public/seller-intelligence/live?category=nope", environment());
  assert.equal(invalidCategory.status, 400);
  assert.deepEqual(await invalidCategory.json(), { error: "invalid_category" });

  const live = await request("/api/public/seller-intelligence/live?profile=seller_alert&category=pressure_washers", environment());
  assert.equal(live.status, 200);
  const liveText = await live.text();
  assert.match(liveText, /seller-alert\/daily\/2026-08-24\/pressure_washers\.json/);
  assert.doesNotMatch(liveText, /INSERT|UPDATE|DELETE|C:\\Users|secret/i);

  const failedLive = await request(
    "/api/public/seller-intelligence/live?profile=seller_alert&category=pressure_washers",
    environment({ throwOnLiveRead: true }),
  );
  assert.equal(failedLive.status, 503);
  assert.deepEqual(await failedLive.json(), { error: "unavailable" });

  const failedList = await request("/api/public/seller-intelligence", environment({ throwOnList: true }));
  assert.equal(failedList.status, 200);
  assert.deepEqual(await failedList.json(), { reports: [] });
});

test("live seller intelligence uses the shared analytical market universe", async () => {
  const { buildLiveSellerIntelligence } = await loadSellerIntelligenceModule();
  const data = completeSellerAlertDashboard();
  data.productMetadata = data.categoryRows[0].observations.slice(0, 4).map((item, index) => ({
    asin: item.asin,
    productType: index < 3 ? ["electric_pressure_washer", "gas_pressure_washer", "cordless_pressure_washer"][index] : "surface_cleaner",
  }));
  const report = await buildLiveSellerIntelligence(data, {
    profile: "seller_alert",
    categoryKey: "pressure_washers",
    context: { marketplace: "US", category: "pressure_washers", segment: "machines" },
  });
  assert.equal(report.evidence.sampleSize, 3);
});
