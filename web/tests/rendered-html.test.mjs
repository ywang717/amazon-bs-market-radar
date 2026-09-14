import assert from "node:assert/strict";
import { register } from "node:module";
import test from "node:test";
import { categories } from "../lib/catalog.ts";

const workerEnvironment = globalThis.__dashboardWorkerEnvironment ??= {};
register(`data:text/javascript,export async function resolve(specifier, context, nextResolve) { if (specifier === "cloudflare:workers") return { url: "data:text/javascript,export const env = globalThis.__dashboardWorkerEnvironment", shortCircuit: true }; return nextResolve(specifier, context); }`, import.meta.url);

function dynamicD1Environment(marketDate, { disjointAsins = false, previousDate = "2026-08-12", priceAsString = false, missingCurrent = false, discountedProduct = false, allCategoryMetadata = false, strongSignal = false, stableSignals = false, universeProbe = false } = {}) {
  const dates = [previousDate, marketDate];
  const snapshots = dates.map((market_date) => ({ market_date, observed_at: `${market_date}T09:00:00Z`, complete_category_count: 3 }));
  const categoryDays = dates.flatMap((market_date) => categories.map((category) => ({ market_date, category_key: category.key, observation_count: 30, complete: 1, missing_ranks_json: "[]" })));
  const observations = dates.flatMap((market_date) => categories.flatMap((category) => Array.from({ length: 30 }, (_, index) => {
    const rank = index + 1;
    const isProbeMachine = universeProbe && category.key === "pressure_washers"
      && rank === (market_date === marketDate ? 1 : 18);
    const isProbeAccessory = universeProbe && category.key === "pressure_washers"
      && rank === (market_date === marketDate ? 5 : 20);
    const asin = isProbeMachine
      ? "B000000001"
      : isProbeAccessory
        ? "B000000002"
        : !disjointAsins && category.key === "pressure_washers" && rank === (market_date === marketDate || stableSignals ? 4 : strongSignal ? 26 : 12)
          ? "B123456789"
          : `${category.key === "pressure_washers" ? "PRE" : category.key === "sump_pumps" ? "SUM" : "ACC"}${disjointAsins ? market_date.replaceAll("-", "") : ""}${String(rank).padStart(7, "0")}`;
    const isDiscounted = discountedProduct && category.key === "pressure_washers" && rank === 1;
    const title = isProbeMachine ? "Machine Universe Probe"
      : isProbeAccessory ? "15 Inch Surface Cleaner"
        : `${category.short} ${rank}`;
    return { market_date, category_key: category.key, rank, asin, title, url: `https://www.amazon.com/dp/${asin}`, price: isDiscounted ? (priceAsString ? "79.99" : 79.99) : (priceAsString ? "20.00" : 20), rating: 4.5, reviews: 100, has_discount: isDiscounted, discounts_json: isDiscounted ? JSON.stringify([{ kind: "PRICE_DROP", amount: "$186.89 off" }]) : "[]" };
  }))).filter((row) => !(missingCurrent && row.market_date === marketDate && row.category_key === "sump_pumps" && row.rank === 30));
  const metadataRows = [...new Map(observations.filter(({ category_key }) => allCategoryMetadata || category_key === "pressure_washers").map((row) => [row.asin, row])).values()].map((row) => {
    const accessory = row.category_key === "pressure_washer_accessories" || row.rank % 5 === 0;
    const accessoryTypes = ["surface_cleaner", "pressure_washer_gun", "hose", "nozzle", "other_accessory"];
    const productType = row.category_key === "pressure_washer_accessories" ? accessoryTypes[(row.rank - 1) % accessoryTypes.length] : accessory ? "surface_cleaner" : "electric_pressure_washer";
    const brand = row.asin === "B000000001" ? "Westinghouse"
      : accessory ? "Accessory Co" : ["Westinghouse", "Greenworks", "MZK"][row.rank % 3];
    const rawBrand = row.asin === "B000000001" ? "Raw Marketplace Brand" : brand;
    return {
      marketplace: "AMAZON_US", asin: row.asin, product_type: productType,
      classification_confidence: "high", classification_rule_id: accessory ? "accessory-surface-cleaner" : "machine-electric",
      classification_rule_version: "product-rules-v1", classification_evidence_json: "[]", raw_brand: rawBrand,
      normalized_brand: brand, normalized_brand_key: brand.toLowerCase(), brand_alias_rule_id: null, brand_source: "verified_metadata",
      first_seen_market_date: previousDate, last_seen_market_date: marketDate,
    };
  });
  const DB = {
    prepareCalls: 0,
    prepare(sql) {
      this.prepareCalls += 1;
      let values = [];
      return {
        bind(...bound) { values = bound; return this; },
        async first() { return null; },
        async all() {
          if (sql.includes("FROM snapshots")) return { results: snapshots };
          if (sql.includes("FROM category_days")) return { results: categoryDays };
          if (sql.includes("WHERE o.asin")) return { results: observations.filter((row) => row.asin === values[0]) };
          if (sql.includes("FROM product_metadata")) return { results: metadataRows };
          if (sql.includes("FROM observations")) return { results: observations };
          return { results: [] };
        },
      };
    },
    async batch() { return []; },
  };
  return { DB, ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } };
}

function sellerIntelligenceEnvironment({
  completeMarketDays = 6,
  focusTitle = "2000 PSI 1.8 GPM Electric Pressure Washer with 25 FT Hose",
  incompleteCategoryKeys = [],
  lowCoverageCategoryKeys = [],
  reviewChange = false,
} = {}) {
  const latestDate = "2026-08-24";
  const priorDates = Array.from({ length: Math.max(completeMarketDays - 1, 0) }, (_, index) => `2026-08-${String(23 - index).padStart(2, "0")}`);
  const dates = [...priorDates.reverse(), latestDate];
  const archivedKey = "seller-alert/daily/2026-08-24/pressure_washers.json";
  const archivedStrategyKey = "competition-strategy/weekly/2026-08-24/pressure_washers.json";
  const archivedReport = {
    schemaVersion: "seller-intelligence-v1",
    key: archivedKey,
    reportKind: "daily",
    profile: "seller_alert",
    marketDate: latestDate,
    categoryKey: "pressure_washers",
    generatedAt: "2026-08-25T01:00:00Z",
    generatorVersion: "seller-rules-v1",
    contentSha256: "a".repeat(64),
    evidence: {
      complete: true,
      completeMarketDays,
      sampleSize: 30,
      fieldCoverage: {
        price: 100,
        rating: 100,
        reviews: 100,
        discount: 100,
        specs: 0,
      },
    },
    signals: [
      {
        priority: "high",
        kind: "rank_move",
        asin: "B123456789",
        currentRank: 4,
        previousRank: 26,
        checks: ["核查价格与优惠状态", "核查标题规格"],
        evidence: ["高压清洗机中该商品排名由 #26 变为 #4"],
      },
    ],
    sections: [
      {
        title: "经营预警",
        statements: ["高压清洗机当前与上一完整市场日均为完整 Top 30，仅输出可核查的公开变化。"],
      },
      {
        title: "数据质量",
        statements: ["比较基线为 2026-08-23，仅展示公开可验证的名次变化，不推断原因。"],
      },
    ],
    limitations: [
      "描述性观察，不代表销量、利润或选品成功预测。",
      "缺失字段保持为空，不以零值代替未采集或未验证的数据。",
    ],
  };
  const archivedStrategyReport = {
    schemaVersion: "seller-intelligence-v1",
    key: archivedStrategyKey,
    reportKind: "weekly",
    profile: "competition_strategy",
    marketDate: latestDate,
    categoryKey: "pressure_washers",
    generatedAt: "2026-08-25T01:00:00Z",
    generatorVersion: "seller-rules-v1",
    contentSha256: "b".repeat(64),
    evidence: {
      complete: true,
      completeMarketDays,
      sampleSize: 30,
      fieldCoverage: {
        price: 100,
        rating: 100,
        reviews: 100,
        discount: 100,
        specs: 0,
      },
    },
    signals: [],
    sections: [
      {
        title: "竞争策略",
        statements: ["高压清洗机已形成完整市场日窗口，仅输出描述性竞争观察。"],
      },
      {
        title: "字段覆盖",
        statements: ["价格字段覆盖率约 100%，可作为区间观察的辅助证据。"],
      },
      {
        title: "下周观察",
        statements: ["Top 10 留存共 9 个席位，适合继续人工核查头部商品的详情页与价格状态。"],
      },
    ],
    limitations: [
      "描述性观察，不代表销量、利润或选品成功预测。",
      "缺失字段保持为空，不以零值代替未采集或未验证的数据。",
    ],
  };

  const snapshots = dates.map((market_date) => ({
    market_date,
    observed_at: `${market_date}T09:00:00Z`,
    complete_category_count: 3,
  }));
  const categoryDays = dates.flatMap((market_date) => categories.map((category) => ({
    market_date,
    category_key: category.key,
    observation_count: market_date === latestDate && incompleteCategoryKeys.includes(category.key) ? 29 : 30,
    complete: market_date === latestDate && incompleteCategoryKeys.includes(category.key) ? 0 : 1,
    missing_ranks_json: "[]",
  })));
  const observations = dates.flatMap((market_date) => categories.flatMap((category) => Array.from({ length: 30 }, (_, index) => {
    const rank = index + 1;
    const isCurrentWasherFocus = market_date === latestDate && category.key === "pressure_washers" && rank === 4;
    const isPreviousWasherFocus = market_date === "2026-08-23" && category.key === "pressure_washers" && rank === 26;
    const asin = isCurrentWasherFocus || isPreviousWasherFocus
      ? "B123456789"
      : `${category.key.slice(0, 3).toUpperCase()}${market_date.replaceAll("-", "").slice(-5)}${String(rank).padStart(2, "0")}`;
    const discounted = category.key === "pressure_washers" && rank === 4;
    return {
      market_date,
      category_key: category.key,
      rank,
      asin,
      title: isCurrentWasherFocus || isPreviousWasherFocus
        ? focusTitle
        : `${category.short} ${rank}`,
      url: `https://www.amazon.com/dp/${asin}`,
      price: lowCoverageCategoryKeys.includes(category.key) && market_date === latestDate && rank > 9
        ? null
        : category.key === "pressure_washers" && rank === 4 ? 199.99 : 100 + rank,
      rating: lowCoverageCategoryKeys.includes(category.key) && market_date === latestDate && rank > 9
        ? null
        : category.key === "pressure_washers" && rank === 4 ? 4.8 : 4.5,
      reviews: lowCoverageCategoryKeys.includes(category.key) && market_date === latestDate && rank > 9
        ? null
        : reviewChange && category.key === "pressure_washers" && (isCurrentWasherFocus || isPreviousWasherFocus) ? (isPreviousWasherFocus ? 8949 : 8977)
          : category.key === "pressure_washers" && rank === 4 ? 128 : 100 + rank,
      has_discount: discounted ? 1 : 0,
      discounts_json: discounted ? JSON.stringify([{ kind: "COUPON", amount: "10% off" }]) : "[]",
    };
  }).filter((row) => !(market_date === latestDate && incompleteCategoryKeys.includes(category.key) && row.rank === 30))));

  const DB = {
    prepare(sql) {
      let values = [];
      return {
        bind(...bound) {
          values = bound;
          return this;
        },
        async first() {
          if (sql.includes("FROM seller_intelligence_reports WHERE key = ?")) {
            if (values[0] === archivedKey) return { content_json: JSON.stringify(archivedReport) };
            if (values[0] === archivedStrategyKey) return { content_json: JSON.stringify(archivedStrategyReport) };
            return null;
          }
          return null;
        },
        async all() {
          if (sql.includes("FROM snapshots")) return { results: snapshots };
          if (sql.includes("FROM category_days")) return { results: categoryDays };
          if (sql.includes("WHERE o.asin")) return { results: observations.filter((row) => row.asin === values[0]) };
          if (sql.includes("FROM observations")) return { results: observations };
          if (sql.includes("FROM product_metadata")) return { results: [{ marketplace: "AMAZON_US", asin: "B123456789", product_type: "electric_pressure_washer", classification_confidence: "high", classification_rule_id: "machine-electric", classification_rule_version: "product-rules-v1", classification_evidence_json: "[]", raw_brand: "Greenworks", normalized_brand: "Greenworks", normalized_brand_key: "greenworks", brand_alias_rule_id: null, brand_source: "verified_metadata", first_seen_market_date: "2026-08-23", last_seen_market_date: latestDate }] };
          if (sql.includes("FROM seller_intelligence_reports")) {
            const rows = [
              {
                key: archivedKey,
                report_kind: "daily",
                profile: "seller_alert",
                market_date: latestDate,
                category_key: "pressure_washers",
                generated_at: "2026-08-25T01:00:00Z",
                generator_version: "seller-rules-v1",
                content_sha256: "a".repeat(64),
              },
              {
                key: archivedStrategyKey,
                report_kind: "weekly",
                profile: "competition_strategy",
                market_date: latestDate,
                category_key: "pressure_washers",
                generated_at: "2026-08-25T01:00:00Z",
                generator_version: "seller-rules-v1",
                content_sha256: "b".repeat(64),
              },
              {
                key: "seller-alert/daily/2026-08-23/sump_pumps.json",
                report_kind: "daily",
                profile: "seller_alert",
                market_date: "2026-08-23",
                category_key: "sump_pumps",
                generated_at: "2026-08-24T01:00:00Z",
                generator_version: "seller-rules-v1",
                content_sha256: "c".repeat(64),
              },
            ];
            let filtered = rows;
            let index = 0;
            if (sql.includes("profile = ?")) {
              filtered = filtered.filter((row) => row.profile === values[index]);
              index += 1;
            }
            if (sql.includes("category_key = ?")) {
              filtered = filtered.filter((row) => row.category_key === values[index]);
              index += 1;
            }
            if (sql.includes("market_date = ?")) {
              filtered = filtered.filter((row) => row.market_date === values[index]);
            }
            return {
              results: filtered,
            };
          }
          return { results: [] };
        },
      };
    },
    async batch() { return []; },
  };

  return { DB, ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } };
}

async function render(path = "/", env = {}) {
  for (const key of Reflect.ownKeys(workerEnvironment)) delete workerEnvironment[key];
  Object.assign(workerEnvironment, env);
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);
  return worker.fetch(
    new Request(`http://localhost${path}`, { headers: { accept: "text/html" } }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) }, ...env },
    { waitUntil() {}, passThroughOnException() {} },
  );
}

test("renders the signal-first market dashboard", async () => {
  const response = await render("/", dynamicD1Environment("2026-08-13"));
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /Amazon BS 市场雷达/);
  assert.match(html, /<small>市场情报<\/small>/);
  assert.match(html, /<button class="statusAction"[^>]*>.*数据状态<\/button>/);
  assert.match(html, /Amazon 美国站畅销榜公开页面/);
  assert.match(html, /高压清洗机/);
  assert.match(html, /今日需要关注|市场动态/);
  assert.match(html, /高优先级信号/);
  assert.match(html, /新入榜/);
  assert.match(html, /Top10 稳定度（1D）/);
  assert.match(html, /市场波动/);
  assert.match(html, /品牌变化/);
  assert.match(html, /市场结构/);
  assert.doesNotMatch(html, /MARKET INTELLIGENCE|MARKET SUMMARY|Top10 Stability|Turnover|Top3 Brands|High \/ Watch|vs previous valid market day|Data status/);
  assert.doesNotMatch(html, /分析就绪雷达/);
  assert.doesNotMatch(html, /历史数据质量时间轴/);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/i);
});

test("renders isolated page-local data for all three markets and accessory subsegments", async () => {
  const env = dynamicD1Environment("2026-08-13", { allCategoryMetadata: true });
  const sumpOverview = await render("/?category=sump_pumps&segment=all", env);
  assert.equal(sumpOverview.status, 200);
  const sumpHtml = await sumpOverview.text();
  assert.match(sumpHtml, /<h1>污水泵<\/h1>/);

  const accessoriesOverview = await render("/?category=pressure_washer_accessories&segment=all", env);
  assert.equal(accessoriesOverview.status, 200);
  const accessoriesHtml = await accessoriesOverview.text();
  assert.match(accessoriesHtml, /<h1>高压清洗机配件<\/h1>/);

  const sumpProducts = await render("/products?category=sump_pumps&segment=all", env);
  assert.equal(sumpProducts.status, 200);
  const sumpProductsHtml = await sumpProducts.text();
  assert.match(sumpProductsHtml, /污水泵 1/);
  assert.doesNotMatch(sumpProductsHtml, /清洗机 1<\/span>/);

  const hoses = await render("/products?category=pressure_washer_accessories&segment=hoses", env);
  assert.equal(hoses.status, 200);
  const hoseHtml = await hoses.text();
  assert.match(hoseHtml, /配件 3/);
  assert.doesNotMatch(hoseHtml, /配件 1<\/span>/);

  const hoseRankings = await render("/rankings?category=pressure_washer_accessories&segment=hoses", env);
  assert.equal(hoseRankings.status, 200);
  const hoseRankingsHtml = await hoseRankings.text();
  assert.match(hoseRankingsHtml, /配件 3/);
  assert.doesNotMatch(hoseRankingsHtml, /配件 1<\/span>/);
  assert.doesNotMatch(hoseRankingsHtml, /污水泵 1|清洗机 1<\/span>/);

  const hoseProduct = await render("/products/ACC0000003?category=pressure_washer_accessories&segment=hoses", env);
  assert.equal(hoseProduct.status, 200);
  const hoseProductHtml = await hoseProduct.text();
  assert.match(hoseProductHtml, /配件 3/);
  assert.match(hoseProductHtml, /href="\/products\?date=2026-08-13&amp;category=pressure_washer_accessories&amp;segment=hoses"[^>]*>← 返回产品列表<\/a>/);

  const mismatchedProduct = await render("/products/ACC0000003?category=pressure_washer_accessories&segment=nozzles", env);
  assert.equal(mismatchedProduct.status, 404);

  const sumpReports = await render("/reports?category=sump_pumps&segment=all", env);
  assert.equal(sumpReports.status, 200);
  const sumpReportsHtml = await sumpReports.text();
  assert.match(sumpReportsHtml, /污水泵/);
  assert.match(sumpReportsHtml, /\/analysis\?date=2026-08-13&amp;workspace=seller_alert&amp;category=sump_pumps&amp;segment=all/);
  assert.match(sumpReportsHtml, /日报摘要/);
  assert.match(sumpReportsHtml, /High/);
  assert.match(sumpReportsHtml, /Watch/);
  assert.match(sumpReportsHtml, /市场动态/);
  assert.match(sumpReportsHtml, /细分市场变化/);
  assert.match(sumpReportsHtml, /品牌变化/);
  assert.match(sumpReportsHtml, /证据与方法/);

  const accessoryAlerts = await render("/analysis?workspace=seller_alert&category=pressure_washer_accessories&segment=all", env);
  assert.equal(accessoryAlerts.status, 200);
  const accessoryAlertsHtml = await accessoryAlerts.text();
  assert.match(accessoryAlertsHtml, /高压清洗机配件/);
  assert.match(accessoryAlertsHtml, /name="segment" value="all"/);
});

test("keeps complete valid-day gaps in the seed fallback product timeline", async () => {
  const response = await render("/products/B018H74H74?category=pressure_washer_accessories&segment=all", {});
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /退出 Top30/);
  assert.match(html, /重新入榜/);

  const exitedResponse = await render("/products/B018H74H74?category=pressure_washer_accessories&segment=all&date=2026-08-11", {});
  assert.equal(exitedResponse.status, 200);
  const exitedHtml = await exitedResponse.text();
  assert.match(exitedHtml, /已退出 Top30/);
  assert.match(exitedHtml, /当前排名[\s\S]*—/);
  assert.match(exitedHtml, /最后在榜观测（2026-08-08）/);

  const defaultMachineResponse = await render("/products/B0BVGSX46M", {});
  assert.equal(defaultMachineResponse.status, 200);
  const defaultMachineHtml = await defaultMachineResponse.text();
  assert.doesNotMatch(defaultMachineHtml, /已退出 Top30/);
  assert.match(defaultMachineHtml, /<span class="rankDisplay"><strong>#1<\/strong>/);
});

test("keeps the machines universe aligned across overview products brands and signals while Raw All preserves accessories", async () => {
  const env = dynamicD1Environment("2026-08-13", { allCategoryMetadata: true, universeProbe: true });
  const analyticalPages = [
    await render("/?category=pressure_washers&segment=machines", env),
    await render("/products?category=pressure_washers&segment=machines", env),
    await render("/brands?category=pressure_washers&segment=machines", env),
    await render("/market?category=pressure_washers&segment=machines", env),
  ];
  for (const response of analyticalPages) assert.equal(response.status, 200);
  const [overviewHtml, productsHtml, brandsHtml, marketHtml] = await Promise.all(analyticalPages.map((response) => response.text()));

  assert.match(overviewHtml, /Machine Universe Probe/);
  assert.match(productsHtml, /Machine Universe Probe/);
  assert.match(productsHtml, /Machine Universe Probe[\s\S]*?B000000001[\s\S]*?电动[\s\S]*?<\/td><td>Westinghouse<\/td>/);
  assert.match(brandsHtml, /Westinghouse/);
  assert.match(brandsHtml, /当前市场全部有效席位（(?:<!-- -->)?24(?:<!-- -->)?）/);
  assert.match(marketHtml, /Machine Universe Probe/);
  assert.match(marketHtml, /<dt[^>]*>整机样本(?:<!-- -->)? ⓘ<\/dt><dd>24<\/dd>/);
  for (const html of [overviewHtml, productsHtml, marketHtml]) assert.doesNotMatch(html, /15 Inch Surface Cleaner/);
  assert.doesNotMatch(brandsHtml, /Accessory Co/);

  const rawRankings = await render("/rankings?category=pressure_washers&segment=all", env);
  assert.equal(rawRankings.status, 200);
  const rawRankingsHtml = await rawRankings.text();
  assert.match(rawRankingsHtml, /B000000001/);
  assert.match(rawRankingsHtml, /B000000002/);
  assert.match(rawRankingsHtml, /15 Inch Surface Cleaner/);

  const detail = await render("/products/B000000001?category=pressure_washers&segment=machines", env);
  assert.equal(detail.status, 200);
  const detailHtml = await detail.text();
  assert.match(detailHtml, /Westinghouse.*B000000001.*电动/);
  for (const html of [productsHtml, detailHtml]) assert.doesNotMatch(html, /Raw Marketplace Brand/);
});

test("provides reachable document-navigation destinations for every primary navigation label", async () => {
  const env = dynamicD1Environment("2026-08-13");
  const response = await render("/", env);
  assert.equal(response.status, 200);
  const html = await response.text();
  const navigation = [
    ["/", "总览"],
    ["/market", "市场"],
    ["/products", "产品"],
    ["/brands", "品牌"],
    ["/rankings", "榜单"],
    ["/reports", "报告"],
  ];

  for (const [href, label] of navigation) {
    const escapedHref = href === "/" ? "\\/\\?" : href.replace("/", "\\/") + "\\?";
    const expectedSegment = href === "/rankings" ? "all" : "machines";
    assert.match(html, new RegExp(`<a href="${escapedHref}category=pressure_washers&amp;segment=${expectedSegment}" target="_top"[^>]*>${label}</a>`));
    const target = await render(href, env);
    assert.equal(target.status, 200, `${label} (${href})`);
  }
  const explicitResponse = await render("/?category=pressure_washers&segment=machines", env);
  const explicitHtml = await explicitResponse.text();
  assert.match(explicitHtml, /<a href="\/rankings\?category=pressure_washers&amp;segment=machines" target="_top"[^>]*>榜单<\/a>/);
  assert.match(html, /aria-label="市场动态"/);
  assert.match(html, /aria-label="数据状态"/);
  assert.match(html, /<a[^>]*href="\/methodology\?category=pressure_washers&amp;segment=machines"[^>]*>.*方法说明<\/a>/);
  assert.doesNotMatch(html, /class="sellerAnalysisEntry"/);
});

test("preserves seller analysis as a reachable report workspace", async () => {
  const response = await render("/analysis?workspace=seller_alert&category=pressure_washers&segment=all", dynamicD1Environment("2026-08-13"));
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /在线卖家情报中心/);
});

test("renders dense market intelligence routes with shared product and rank semantics", async () => {
  const env = dynamicD1Environment("2026-08-13");

  const rankings = await render("/rankings", env);
  assert.equal(rankings.status, 200);
  const rankingHtml = await rankings.text();
  assert.match(rankingHtml, /class="productIdentity"/);
  assert.match(rankingHtml, /class="rankDisplay"/);
  assert.match(rankingHtml, /<th>产品<\/th><th>排名<\/th><th>1D变化/);
  assert.doesNotMatch(rankingHtml, /<th>ASIN<\/th>/);

  const products = await render("/products", env);
  assert.equal(products.status, 200);
  const productHtml = await products.text();
  assert.match(productHtml, /搜索 ASIN \/ 产品 \/ 品牌/);
  assert.match(productHtml, /上升/);
  assert.match(productHtml, /Top10/);
  assert.match(productHtml, /新入榜/);
  assert.match(productHtml, /<th>1D<\/th><th[^>]*>7D<\/th>/);
  assert.match(productHtml, /在榜率/);

  const overview = await render("/?category=pressure_washers&segment=machines", env);
  assert.equal(overview.status, 200);
  const overviewHtml = await overview.text();
  assert.match(overviewHtml, /Daily Brief · (?:<!-- -->)?2026-08-13/);
  assert.match(overviewHtml, /Top30 席位变化 · 1D/);

  const market = await render("/market", env);
  assert.equal(market.status, 200);
  const marketHtml = await market.text();
  assert.match(marketHtml, /市场状态/);
  assert.match(marketHtml, /Top10 稳定度/);
  assert.match(marketHtml, /市场分析视图/);
  assert.match(marketHtml, /7(?:<!-- -->)?D/);
  assert.match(marketHtml, /30(?:<!-- -->)?D/);
  assert.match(marketHtml, /整机样本/);
  assert.match(marketHtml, /Top30 商品结构[\s\S]*表面清洁器/);
  assert.doesNotMatch(marketHtml, /view=brands/);
  assert.match(marketHtml, /href="\/brands\?[^"]*category=pressure_washers[^"]*segment=machines/);

  const brands = await render("/brands", env);
  assert.equal(brands.status, 200);
  const brandHtml = await brands.text();
  assert.match(brandHtml, /品牌分布/);
  assert.match(brandHtml, /榜单席位/);
  assert.doesNotMatch(brandHtml, /市场席位/);

  assert.match(marketHtml, /按当前榜单席位，不代表销量份额。/);
  assert.doesNotMatch(marketHtml, /按当前市场席位/);
  assert.match(brandHtml, /席位占比/);

  const reports = await render("/reports", env);
  assert.equal(reports.status, 200);
  const reportHtml = await reports.text();
  assert.match(reportHtml, /智能报告/);
  assert.match(reportHtml, /经营预警/);
  assert.match(reportHtml, /竞争观察/);
  assert.doesNotMatch(reportHtml, /竞争策略/);
  assert.doesNotMatch(reportHtml, /北京时间|北京时区|Beijing|Asia\/Shanghai|UTC\+8|China Standard Time/i);
  assert.match(reportHtml, /细分市场变化[\s\S]*表面清洁器/);
  assert.doesNotMatch(reportHtml, /High \/ Watch/);
});

test("keeps movers and entrants on the 1D valid-market-day contract", async () => {
  const env = dynamicD1Environment("2026-08-13");
  for (const view of ["movers", "entrants"]) {
    const response = await render(`/market?category=pressure_washers&segment=machines&view=${view}&window=30`, env);
    assert.equal(response.status, 200);
    const html = await response.text();
    assert.doesNotMatch(html, /class="marketWindowBar"/);
    assert.doesNotMatch(html, /趋势窗口/);
  }
});

test("renders one report empty state when the market has no signals", async () => {
  const response = await render("/reports?category=pressure_washers&segment=machines", dynamicD1Environment("2026-08-13", { stableSignals: true }));
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /今日暂无 High \/ Watch \/ Activity 市场变化/);
  assert.doesNotMatch(html, /当前没有 High 信号|当前没有 Watch 信号|当前没有普通市场动态/);
  assert.equal(html.match(/class="emptyState"/g)?.length ?? 0, 1);
});

test("builds Top30 product structure from the raw category while preserving the analytical report context", async () => {
  const response = await render("/reports?category=pressure_washers&segment=machines", dynamicD1Environment("2026-08-13"));
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /细分市场变化[\s\S]*表面清洁器/);
});

test("uses the shared compact rank-delta presentation", async () => {
  const response = await render("/rankings?category=pressure_washers&segment=all", dynamicD1Environment("2026-08-13"));
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.doesNotMatch(html, /class="srOnly">名次(?:上升|下降)/);
  assert.match(html, /较上一有效市场日上升 8 名/);
});

test("documents the phase 1 raw and analytical evidence boundaries", async () => {
  const response = await render("/methodology", dynamicD1Environment("2026-08-13"));
  assert.equal(response.status, 200);
  const html = await response.text();

  assert.match(html, /原始榜单/);
  assert.match(html, /分析市场/);
  assert.match(html, /缺少可信品牌证据时标记为“未知”/);
  assert.match(html, /上一有效市场日会跳过失败或不完整市场日/);
  assert.match(html, /可选字段/);
  assert.match(html, /缺失不会影响排名日有效性/);
  assert.match(html, /单类目市场范围的有效日只要求所选类目已持久化为完整且满足精确 Top 30/);
  assert.match(html, /跨类目汇总.*所选多个类目在同一市场日共同有效/);
  assert.doesNotMatch(html, /完整市场日必须包含三个榜单各 30 个唯一 ASIN/);
  assert.match(html, /“首次发现”只表示本系统首次观测到该 ASIN，不代表“新品”/);
  assert.doesNotMatch(html, /Raw Ranking|Analytical Market|Market Context|Exact Top 30|Optional Field|Rank Day Validity|Unknown|Volatility|Turnover|Low|Medium|High|Transparent methodology/);
  assert.match(html, /席位占比/);
  assert.match(html, /Movers/);
  assert.match(html, /Event Feed/);
  assert.match(html, /窗口指标合同/);
  for (const metric of ["Top10 稳定度", "市场更替", "Top3 品牌集中度", "价格中位数", "品牌席位", "商品类型席位"]) assert.match(html, new RegExp(metric));
  assert.doesNotMatch(html, /销量增长|新品监测|新品数量/i);
});

test("renders the latest D1 market day across dashboard pages", async () => {
  const env = dynamicD1Environment("2026-08-13");
  for (const path of ["/", "/rankings", "/insights"]) {
    const response = await render(path, env);
    assert.equal(response.status, 200, path);
    const html = await response.text();
    assert.match(html, /2026-08-13/, path);
    assert.doesNotMatch(html, /746254487|C:\\Users|DAILY_REPORT_SMTP|password/i, path);
  }
});

test("honors a valid market-date deep link and inherits it through primary navigation", async () => {
  const env = dynamicD1Environment("2026-08-13", { previousDate: "2026-08-12" });
  const response = await render("/?category=pressure_washers&segment=machines&date=2026-08-12", env);
  assert.equal(response.status, 200);
  const html = await response.text();

  assert.match(html, /<select[^>]*aria-label="市场日期"[^>]*>/);
  assert.match(html, /<option[^>]*value="2026-08-12"[^>]*selected=""/);
  assert.match(html, /href="\/products\?date=2026-08-12&amp;category=pressure_washers&amp;segment=machines"/);
});

test("keeps market and date context on signal product drill-down links", async () => {
  const response = await render("/?category=pressure_washers&segment=machines&date=2026-08-13", dynamicD1Environment("2026-08-13", { strongSignal: true }));
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /href="\/products\/B123456789\?date=2026-08-13&amp;category=pressure_washers&amp;segment=machines"[^>]*>查看产品/);
});

test("describes an incomplete page-local market day using the actual observation count", async () => {
  const response = await render("/insights?category=sump_pumps&segment=all", dynamicD1Environment("2026-08-13", { missingCurrent: true }));
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /Top30 完整度/);
  assert.match(html, /<strong>29 \/ 30<\/strong>/);
  assert.match(html, /最新 Snapshot 不完整/);
  assert.doesNotMatch(html, /Data Status|Last Update|Complete Market Days|Complete Categories|Missing Snapshots|Coverage|Analysis Ready|Evidence Quality|Data healthy|Incomplete data/);
});

test("renders live rankings when D1 returns decimal prices as strings", async () => {
  const response = await render("/rankings", dynamicD1Environment("2026-08-13", { priceAsString: true }));
  assert.equal(response.status, 200);
  assert.match(await response.text(), /\$20\.00/);
});

test("renders verified rank improvements instead of an unavailable comparison placeholder", async () => {
  const response = await render("/rankings", dynamicD1Environment("2026-08-13"));
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /class="rankDelta up"[^>]*><span aria-hidden="true">↑<\/span>8/);
  assert.doesNotMatch(html, /无连续样本/);
  assert.doesNotMatch(html, /#\d+—/);
});

test("renders verified discounts from the live dashboard on ranking and product pages", async () => {
  const env = dynamicD1Environment("2026-08-13", { discountedProduct: true });
  const rankings = await render("/rankings", env);
  assert.equal(rankings.status, 200);
  const rankingsHtml = await rankings.text();
  assert.match(rankingsHtml, /\$186\.89 OFF/);
  assert.doesNotMatch(rankingsHtml, />Deal</);

  const product = await render("/products/PRE0000001", env);
  assert.equal(product.status, 200);
  const productHtml = await product.text();
  assert.match(productHtml, /优惠/);
  assert.match(productHtml, /\$186\.89 OFF/);
  assert.doesNotMatch(productHtml, /\$30\.00 off|无优惠/);
});

test("does not render unavailable comparison metrics as zero", async () => {
  const response = await render("/", dynamicD1Environment("2026-08-13", { disjointAsins: true }));
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /等待有效比较日/);
  assert.match(html, /<h2>Top10 稳定度（1D）<\/h2>/);
  assert.doesNotMatch(html, /<strong>0%<\/strong><h2>Top10 稳定度（1D）<\/h2>/);
});

test("labels verified fallback data when the live dashboard is unavailable", async () => {
  for (const path of ["/", "/rankings", "/insights"]) {
    const response = await render(path);
    assert.equal(response.status, 200, path);
    const html = await response.text();
    assert.match(html, /实时数据暂不可用/);
    assert.match(html, /已验证回退数据/);
  }
});

test("renders the seed fallback comparison baseline without undefined", async () => {
  const response = await render("/");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /2026-08-12/);
  assert.doesNotMatch(html, />undefined\s*→/);
});

test("labels verified fallback data on a product page", async () => {
  const response = await render("/products/B0BVGSX46M");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /实时数据暂不可用/);
  assert.doesNotMatch(html, /Live data is temporarily unavailable|>[^<]*Reviews<|Rank Timeline|Current Status|Timeline Events|Presence \/ Reviews|>Evidence</);
});

test("renders a D1 product history and returns not found for an unknown ASIN", async () => {
  const env = dynamicD1Environment("2026-08-13", { previousDate: "2026-08-11" });
  const found = await render("/products/B123456789", env);
  assert.equal(found.status, 200);
  const html = await found.text();
  assert.match(html, /2026-08-13/);
  assert.match(html, /#4/);
  assert.match(html, /Greenworks.*B123456789.*电动/);
  assert.match(html, /2(?:<!-- -->)? 个市场日/);
  assert.doesNotMatch(html, /2026-08-12/);

  const missing = await render("/products/B000000000", env);
  assert.equal(missing.status, 404);
});

test("renders exact review change events on product detail", async () => {
  const response = await render("/products/B123456789", sellerIntelligenceEnvironment({ completeMarketDays: 2, reviewChange: true }));
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /评论变化/);
  assert.match(html, /8,949 → 8,977 {2}\+28/);
});

test("rejects malformed product paths before consulting D1", async () => {
  const env = dynamicD1Environment("2026-08-13");
  const response = await render("/products/not-an-asin", env);
  assert.equal(response.status, 404);
  assert.equal(env.DB.prepareCalls, 0);
});

test("renders every public read-only route without internal details", async () => {
  for (const path of ["/rankings", "/insights", "/reports", "/methodology", "/products/B0BVGSX46M"]) {
    const response = await render(path);
    assert.equal(response.status, 200, path);
    const html = await response.text();
    assert.doesNotMatch(html, /746254487|C:\\Users|DAILY_REPORT_SMTP|password/i, path);
  }
});

test("renders seller workspaces, archive filters and evidence-first disclosure", async () => {
  const response = await render("/analysis?workspace=archive&profile=seller_alert&category=pressure_washers&date=2026-08-24&report=seller-alert/daily/2026-08-24/pressure_washers.json", sellerIntelligenceEnvironment());
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /经营预警/);
  assert.match(html, /竞争观察/);
  assert.doesNotMatch(html, /竞争策略/);
  assert.match(html, /历史归档/);
  assert.match(html, /描述性观察/);
  assert.match(html, /2026-08-24/);
  assert.match(html, /经营预警(?:<!-- -->)? · (?:<!-- -->)?高压清洗机(?:<!-- -->)? · (?:<!-- -->)?2026-08-24/);
  assert.doesNotMatch(html, /<span class="mono">seller-alert\/daily\/2026-08-24\/pressure_washers\.json<\/span>/);
  assert.match(html, /href="\/products\/B123456789\?date=2026-08-24&amp;category=pressure_washers&amp;segment=machines"/);
  assert.doesNotMatch(html, /销量预测|利润预测|C:\\Users|SMTP/i);
});

test("keeps the original realtime and archive report center reachable beside seller workspaces", async () => {
  const response = await render("/analysis?category=pressure_washers&segment=all", sellerIntelligenceEnvironment());
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /实时解读/);
  assert.match(html, /历史智能报告/);
  assert.match(html, /经营预警/);
  assert.match(html, /竞争观察/);
  assert.doesNotMatch(html, /竞争策略/);
  assert.match(html, /href="\/analysis\?date=2026-08-24&amp;workspace=seller_alert/);
});

test("archive workspace filters change which reports render in the UI", async () => {
  const sellerAlert = await render("/analysis?workspace=archive&profile=seller_alert&category=pressure_washers&date=2026-08-24", sellerIntelligenceEnvironment());
  assert.equal(sellerAlert.status, 200);
  const sellerAlertHtml = await sellerAlert.text();
  assert.match(sellerAlertHtml, /seller-alert\/daily\/2026-08-24\/pressure_washers\.json/);
  assert.doesNotMatch(sellerAlertHtml, /competition-strategy\/weekly\/2026-08-24\/pressure_washers\.json/);
  assert.doesNotMatch(sellerAlertHtml, /seller-alert\/daily\/2026-08-23\/sump_pumps\.json/);

  const strategy = await render("/analysis?workspace=archive&profile=competition_strategy&category=pressure_washers&date=2026-08-24", sellerIntelligenceEnvironment());
  assert.equal(strategy.status, 200);
  const strategyHtml = await strategy.text();
  assert.match(strategyHtml, /competition-strategy\/weekly\/2026-08-24\/pressure_washers\.json/);
  assert.doesNotMatch(strategyHtml, /seller-alert\/daily\/2026-08-24\/pressure_washers\.json/);
  assert.doesNotMatch(strategyHtml, /seller-alert\/daily\/2026-08-23\/sump_pumps\.json/);

  const sumpPump = await render("/analysis?workspace=archive&profile=seller_alert&category=sump_pumps&date=2026-08-23", sellerIntelligenceEnvironment());
  assert.equal(sumpPump.status, 200);
  const sumpPumpHtml = await sumpPump.text();
  assert.match(sumpPumpHtml, /seller-alert\/daily\/2026-08-23\/sump_pumps\.json/);
  assert.doesNotMatch(sumpPumpHtml, /seller-alert\/daily\/2026-08-24\/pressure_washers\.json/);
  assert.doesNotMatch(sumpPumpHtml, /competition-strategy\/weekly\/2026-08-24\/pressure_washers\.json/);
});

test("renders live and archived seller evidence boundaries with five required elements", async () => {
  const live = await render("/analysis?workspace=competition_strategy&category=pressure_washers&segment=all", sellerIntelligenceEnvironment());
  assert.equal(live.status, 200);
  const liveHtml = await live.text();
  assert.match(liveHtml, /数据范围/);
  assert.match(liveHtml, /截至 2026-08-24 的完整市场日窗口（6 日）/);
  assert.match(liveHtml, /样本量/);
  assert.match(liveHtml, /完整度/);
  assert.match(liveHtml, /证据充分度/);
  assert.match(liveHtml, /仅描述可验证公开事实，不代表因果关系。/);

  const archived = await render("/analysis?workspace=archive&profile=seller_alert&category=pressure_washers&date=2026-08-24&report=seller-alert/daily/2026-08-24/pressure_washers.json", sellerIntelligenceEnvironment());
  assert.equal(archived.status, 200);
  const archivedHtml = await archived.text();
  assert.match(archivedHtml, /数据范围/);
  assert.match(archivedHtml, /市场日 2026-08-24/);
  assert.match(archivedHtml, /样本量/);
  assert.match(archivedHtml, /完整度/);
  assert.match(archivedHtml, /证据充分度/);
  assert.match(archivedHtml, /仅描述可验证公开事实，不代表因果关系。/);
});

test("uses seller workspace navigation links instead of incomplete aria tabs", async () => {
  const response = await render("/analysis?workspace=competition_strategy&category=pressure_washers&segment=all", sellerIntelligenceEnvironment());
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /<nav class="tabs" aria-label="卖家情报工作区">/);
  assert.match(html, /aria-current="page"[^>]*>竞争观察</);
  assert.doesNotMatch(html, /role="tablist"/);
  assert.doesNotMatch(html, /role="tab"/);
  assert.doesNotMatch(html, /aria-selected=/);
});

test("uses the strategy empty state below five complete days", async () => {
  const response = await render("/analysis?workspace=competition_strategy&category=pressure_washers&segment=all", sellerIntelligenceEnvironment({ completeMarketDays: 4 }));
  assert.equal(response.status, 200);
  assert.match(await response.text(), /数据积累中，暂不输出稳定趋势/);
});

test("keeps strategy on the previous valid day when the latest category day is incomplete", async () => {
  const incomplete = await render("/analysis?workspace=competition_strategy&category=sump_pumps", sellerIntelligenceEnvironment({ incompleteCategoryKeys: ["sump_pumps"] }));
  assert.equal(incomplete.status, 200);
  const incompleteHtml = await incomplete.text();
  assert.match(incompleteHtml, /截至 2026-08-23 的完整市场日窗口/);
  assert.doesNotMatch(incompleteHtml, /当前数据不完整，暂不下结论/);

  const lowCoverage = await render("/analysis?workspace=competition_strategy&category=pressure_washers&segment=all", sellerIntelligenceEnvironment({ lowCoverageCategoryKeys: ["pressure_washers"] }));
  assert.equal(lowCoverage.status, 200);
  assert.match(await lowCoverage.text(), /价格字段覆盖不足 80%.*暂不输出价格带观察/);
});

test("shows only explicit seller specs on the product drilldown", async () => {
  const response = await render("/products/B123456789?category=pressure_washers&segment=all", sellerIntelligenceEnvironment());
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /产品事实/);
  assert.match(html, /2000 PSI/);
  assert.match(html, /1\.8 GPM/);
  assert.match(html, /25 FT/);
  assert.doesNotMatch(html, /规格.*0(?:\.0+)?/);
});

test("shows a seller evidence boundary on the product drilldown", async () => {
  const response = await render("/products/B123456789?category=pressure_washers&segment=all", sellerIntelligenceEnvironment());
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /产品事实/);
  assert.match(html, /数据范围/);
  assert.match(html, /2026-08-23 至 2026-08-24/);
  assert.match(html, /样本量/);
  assert.match(html, /完整度/);
  assert.match(html, /证据充分度/);
  assert.match(html, /仅描述可验证公开事实，不代表因果关系。/);
});

test("does not infer missing or ambiguous product specifications", async () => {
  const noSpecs = await render("/products/B123456789?category=pressure_washers&segment=all", sellerIntelligenceEnvironment({ focusTitle: "Compact Washer for Patio Cleaning" }));
  assert.equal(noSpecs.status, 200);
  const noSpecsHtml = await noSpecs.text();
  assert.doesNotMatch(noSpecsHtml, /产品事实/);
  assert.doesNotMatch(noSpecsHtml, /sellerSpecList/);

  const ambiguous = await render("/products/B123456789?category=pressure_washers&segment=all", sellerIntelligenceEnvironment({ focusTitle: "1800 PSI Degasser Electric Washer with 50 FT CORD" }));
  assert.equal(ambiguous.status, 200);
  const ambiguousHtml = await ambiguous.text();
  assert.match(ambiguousHtml, /1800 PSI/);
  assert.match(ambiguousHtml, /Electric/);
  assert.match(ambiguousHtml, /50 FT/);
  assert.doesNotMatch(ambiguousHtml, /<dt>动力类型<\/dt><dd>Gas<\/dd>/);
  assert.doesNotMatch(ambiguousHtml, /<dt>软管长度<\/dt><dd>50 FT<\/dd>/);
});

test("binds mixed hose and cord lengths to their own objects", async () => {
  const response = await render("/products/B123456789?category=pressure_washers&segment=all", sellerIntelligenceEnvironment({ focusTitle: "2000 PSI Electric Washer with 50 FT CORD WITH 25 FT HOSE" }));
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /<dt>电源线长度<\/dt><dd>50 FT<\/dd>/);
  assert.match(html, /<dt>软管长度<\/dt><dd>25 FT<\/dd>/);
  assert.doesNotMatch(html, /<dt>软管长度<\/dt><dd>50 FT<\/dd>/);
});
