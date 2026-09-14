import assert from "node:assert/strict";
import test from "node:test";
import {
  buildBrandMovement,
  buildBrandStructure,
  buildAnalyticalCategory,
  buildClassificationCoverage,
  buildMarketSignals,
  groupMarketSignals,
  buildMarketState,
  buildMarketTrend,
  buildBrandSeatTrend,
  buildProductRows,
  buildProductRankTimeline,
  resolveProductTimelineStatus,
  buildProductTypeStructure,
  buildWorthStudyingProducts,
  buildReviewCompetition,
  resolveCanonicalEventState,
  activityPriorityPresentation,
  compactProductTitle,
  productDisplayName,
  formatCompactNumber,
  formatExactNumber,
  formatReviewChange,
  formatPrice,
  formatDeal,
  formatRating,
  formatPercentage,
  formatCompactDate,
  formatMarketDate,
  marketContextForCategory,
  validateDealDisplay,
} from "../lib/ui-intelligence.ts";
import { getSeedDashboard } from "../lib/dashboard-data.ts";
import { filterAnalyticalMarket } from "../lib/market-context.ts";

const observation = (asin, rank, title = `Product ${asin}`, overrides = {}) => ({
  asin,
  rank,
  title,
  url: `https://www.amazon.com/dp/${asin}`,
  price: 99.99,
  rating: 4.5,
  reviews: 1200,
  has_discount: false,
  discounts: [],
  ...overrides,
});

const metadata = (asin, normalizedBrand, productType = "electric_pressure_washer") => ({
  marketplace: "AMAZON_US",
  asin,
  productType,
  classificationConfidence: productType === "unknown" ? "low" : "high",
  classificationRuleId: productType === "unknown" ? null : "product-rule-v1",
  classificationRuleVersion: "product-rules-v1",
  classificationEvidence: [],
  rawBrand: normalizedBrand,
  normalizedBrand,
  normalizedBrandKey: normalizedBrand?.toLowerCase() ?? null,
  brandAliasRuleId: null,
  brandSource: normalizedBrand ? "verified_metadata" : "unknown",
  firstSeenMarketDate: "2026-08-26",
  lastSeenMarketDate: "2026-08-27",
});

test("uses one analytical universe while preserving the pressure-washer raw ranking", () => {
  const machine = observation("B000000001", 1, "Westinghouse Electric Pressure Washer");
  const accessory = observation("B000000002", 2, "15 Inch Surface Cleaner");
  const metadataFixture = [
    metadata(machine.asin, "Westinghouse", "electric_pressure_washer"),
    metadata(accessory.asin, "Generic", "surface_cleaner"),
  ];
  const categoryFixture = {
    key: "pressure_washers",
    label: "高压清洗机",
    marketDate: "2026-09-02",
    observations: [machine, accessory],
    previousObservations: [],
    comparison: { ready: false, movers: [] },
  };
  const machinesContext = { marketplace: "US", category: "pressure_washers", segment: "machines" };
  const rawContext = { marketplace: "US", category: "pressure_washers", segment: "all" };
  const analytical = buildAnalyticalCategory(categoryFixture, metadataFixture, machinesContext);

  assert.deepEqual(analytical.observations.map(({ asin }) => asin).toSorted(), ["B000000001"]);
  assert.deepEqual(filterAnalyticalMarket(categoryFixture.observations, metadataFixture, rawContext).map(({ asin }) => asin).toSorted(), ["B000000001", "B000000002"]);

  const comparable = buildAnalyticalCategory({
    ...categoryFixture,
    previousObservations: [{ ...machine, rank: 20 }, { ...accessory, rank: 10 }],
    comparison: { ready: true, baselineDate: "2026-09-01", movers: [] },
  }, metadataFixture, machinesContext);
  const overviewAsins = comparable.observations.map(({ asin }) => asin).toSorted();
  const productAsins = buildProductRows({
    observations: comparable.observations,
    comparison: comparable.comparison,
    metadata: metadataFixture,
  }).map(({ asin }) => asin).toSorted();
  const brandStructure = buildBrandStructure(comparable.observations, metadataFixture);
  const signalAsins = buildMarketSignals({ categoryRows: [comparable], productMetadata: metadataFixture })
    .flatMap(({ asin }) => asin === null ? [] : [asin]).toSorted();

  assert.deepEqual(overviewAsins, ["B000000001"]);
  assert.deepEqual(productAsins, overviewAsins);
  assert.deepEqual(signalAsins, overviewAsins);
  assert.equal(brandStructure.denominator, overviewAsins.length);
  assert.deepEqual(brandStructure.rows.map(({ brand, seats }) => [brand, seats]), [["Westinghouse", 1]]);
});

test("uses only High Watch Activity and promotes Top10 boundary events to High", () => {
  const current = [
    observation("B000000001", 5, "Fast riser"),
    observation("B000000002", 20, "Falling product"),
    observation("B000000003", 9, "New entry"),
  ];
  const previous = [
    observation("B000000001", 30, "Fast riser"),
    observation("B000000002", 5, "Falling product"),
    observation("B000000004", 9, "Exited product"),
  ];
  const dashboard = {
    categoryRows: [{
      key: "pressure_washers", marketDate: "2026-08-27",
      label: "高压清洗机",
      observations: current,
      previousObservations: previous,
      comparison: {
        ready: true,
        baselineDate: "2026-08-26",
        averageAbsoluteMove: 13.3,
        top10Retained: 0,
        entries: 1,
        exits: 1,
        movers: [
          { ...current[0], previousRank: 30, change: 25, absoluteMove: 25 },
          { ...current[1], previousRank: 5, change: -15, absoluteMove: 15 },
        ],
      },
    }],
  };

  const signals = buildMarketSignals(dashboard);

  assert.deepEqual(signals.map(({ level, kind, asin }) => [level, kind, asin]), [
    ["high", "top10_entry", "B000000001"],
    ["high", "top10_exit", "B000000002"],
    ["high", "new_entry", "B000000003"],
    ["high", "exit", "B000000004"],
  ]);
  assert.equal(signals[0].delta, 25);
  assert.equal(signals[0].evidence, "High");
});

test("deduplicates the same market product date and event at the highest severity", () => {
  const current = [observation("B000000001", 5)];
  const previous = [observation("B000000001", 30)];
  const row = {
    key: "pressure_washers", label: "高压清洗机", marketDate: "2026-08-27",
    observations: current, previousObservations: previous,
    comparison: { ready: true, baselineDate: "2026-08-26", movers: [{ ...current[0], previousRank: 30, change: 25, absoluteMove: 25 }] },
  };
  const signals = buildMarketSignals({ categoryRows: [row, { ...row, label: "重复来源" }] });
  assert.equal(signals.filter(({ kind }) => kind === "top10_entry").length, 1);
  assert.equal(signals[0].level, "high");
  assert.equal(signals[0].marketDate, "2026-08-27");
});

test("validates deal display without mutating captured values", () => {
  const raw = { currentPrice: 80, referencePrice: 100, discount: 20, hasDiscount: true, label: "$20 OFF" };
  assert.deepEqual(validateDealDisplay(raw), { valid: true, label: "$20 OFF" });
  assert.deepEqual(raw, { currentPrice: 80, referencePrice: 100, discount: 20, hasDiscount: true, label: "$20 OFF" });
  assert.deepEqual(validateDealDisplay({ ...raw, referencePrice: 70 }), { valid: false, label: "优惠信息待确认" });
  assert.deepEqual(validateDealDisplay({ ...raw, discount: -1 }), { valid: false, label: "优惠信息待确认" });
  assert.deepEqual(validateDealDisplay({ ...raw, currentPrice: null }), { valid: false, label: "优惠信息待确认" });
  assert.deepEqual(validateDealDisplay({ ...raw, hasDiscount: false }), { valid: true, label: "—" });
});

test("keeps a verified Amazon saving even when it exceeds current price", () => {
  assert.deepEqual(validateDealDisplay({
    currentPrice: 79.99,
    referencePrice: 266.88,
    discount: 186.89,
    hasDiscount: true,
    label: "$186.89 OFF",
  }), { valid: true, label: "$186.89 OFF" });
  assert.equal(formatDeal({
    price: 79.99,
    has_discount: true,
    discounts: [{ kind: "PRICE_DROP", amount: "$186.89 off" }],
  }), "$186.89 OFF");
});

test("fails closed for malformed deal evidence", () => {
  assert.deepEqual(validateDealDisplay({ currentPrice: 79.99, referencePrice: 266.88, discount: -1, hasDiscount: true }), {
    valid: false,
    label: "优惠信息待确认",
  });
});

test("creates price coupon and review signals only from comparable non-missing values", () => {
  const current = [observation("B000000001", 5, "Comparable", { price: 80, reviews: 1300, has_discount: true, discounts: [{ kind: "COUPON", amount: "$20 OFF" }] })];
  const previous = [observation("B000000001", 5, "Comparable", { price: 100, reviews: 1000, has_discount: false, discounts: [] })];
  const row = { key: "pressure_washers", label: "高压清洗机", marketDate: "2026-08-27", observations: current, previousObservations: previous, comparison: { ready: true, baselineDate: "2026-08-26", movers: [{ ...current[0], previousRank: 5, change: 0, absoluteMove: 0 }] } };
  assert.deepEqual(buildMarketSignals({ categoryRows: [row] }).map(({ kind, level }) => [kind, level]), [
    ["price_change", "watch"], ["coupon_added", "watch"], ["review_momentum", "watch"],
  ]);
  const missing = { ...row, observations: [observation("B000000001", 5, "Missing", { price: null, reviews: null, has_discount: null })] };
  assert.deepEqual(buildMarketSignals({ categoryRows: [missing] }), []);
});

test("classifies small rank changes as Activity and re-entry as Watch", () => {
  const current = [observation("MOVE", 13), observation("RETURN", 25)];
  const previous = [observation("MOVE", 15)];
  const row = {
    key: "pressure_washers", label: "高压清洗机", marketDate: "2026-08-27", observations: current, previousObservations: previous,
    comparison: { ready: true, baselineDate: "2026-08-26", movers: [{ ...current[0], previousRank: 15, change: 2, absoluteMove: 2 }] },
    history: [{ marketDate: "2026-08-25", observations: [observation("RETURN", 20)] }, { marketDate: "2026-08-26", observations: previous }, { marketDate: "2026-08-27", observations: current }],
  };
  assert.deepEqual(buildMarketSignals({ categoryRows: [row] }).map(({ kind, level }) => [kind, level]), [["re_entry", "watch"], ["rank_surge", "activity"]]);
});

test("preserves High precedence when a returning product re-enters inside Top10", () => {
  const current = [observation("RETURN0001", 8)];
  const previous = [];
  const row = {
    key: "pressure_washers", label: "高压清洗机", marketDate: "2026-08-27", observations: current, previousObservations: previous,
    comparison: { ready: true, baselineDate: "2026-08-26", movers: [] },
    history: [{ marketDate: "2026-08-25", observations: [observation("RETURN0001", 18)] }, { marketDate: "2026-08-26", observations: previous }, { marketDate: "2026-08-27", observations: current }],
  };
  assert.deepEqual(buildMarketSignals({ categoryRows: [row] }).map(({ kind, level }) => [kind, level]), [["re_entry", "high"]]);
});

test("creates verified brand expansion and contraction signals but excludes Unknown", () => {
  const previous = [observation("B000000001", 1), observation("B000000002", 2), observation("B000000003", 3), observation("B000000004", 4)];
  const current = [observation("B000000001", 1), observation("B000000005", 2), observation("B000000006", 3), observation("B000000007", 4)];
  const row = { key: "pressure_washers", label: "高压清洗机", marketDate: "2026-08-27", observations: current, previousObservations: previous, comparison: { ready: true, baselineDate: "2026-08-26", movers: [{ ...current[0], previousRank: 1, change: 0, absoluteMove: 0 }] } };
  const productMetadata = [
    metadata("B000000001", "Stable"), metadata("B000000002", "Falling"), metadata("B000000003", "Falling"), metadata("B000000004", null, "unknown"),
    metadata("B000000005", "Rising"), metadata("B000000006", "Rising"), metadata("B000000007", null, "unknown"),
  ];
  const brandSignals = buildMarketSignals({ categoryRows: [row], productMetadata }).filter(({ kind }) => kind.startsWith("brand_"));
  assert.deepEqual(brandSignals.map(({ level, kind, brand, previousValue, currentValue }) => [level, kind, brand, previousValue, currentValue]), [
    ["high", "brand_contraction", "Falling", 2, 0],
    ["high", "brand_expansion", "Rising", 0, 2],
  ]);
});

test("does not create signals or market claims without a verified comparison", () => {
  const dashboard = {
    categoryRows: [{
      key: "pressure_washers",
      label: "高压清洗机",
      observations: [observation("B000000001", 1)],
      previousObservations: [],
      comparison: { ready: false, reason: "需要相邻两个完整 Top 30 市场日", baselineDate: null, movers: [] },
    }],
  };

  assert.deepEqual(buildMarketSignals(dashboard), []);
  assert.deepEqual(buildMarketState(dashboard.categoryRows[0]), {
    ready: false,
    top10Stability: null,
    volatility: null,
    turnover: null,
  });
});

test("builds fallback signals from the verified previous market day", () => {
  const dashboard = getSeedDashboard();
  const pressureWashers = dashboard.categoryRows.find((row) => row.key === "pressure_washers");
  const signals = buildMarketSignals({ categoryRows: [pressureWashers] });

  assert.ok(pressureWashers.previousObservations.length > 0);
  assert.ok(signals.length > 0);
});

test("maps existing comparison values to named market state without a synthetic score", () => {
  const state = buildMarketState({
    comparison: {
      ready: true,
      top10Retained: 9,
      averageAbsoluteMove: 6.2,
      entries: 3,
      exits: 2,
    },
  });

  assert.deepEqual(state, {
    ready: true,
    top10Stability: 90,
    volatility: "HIGH",
    turnover: "MEDIUM",
  });
});

test("projects every analytical fact to machines without mutating the raw Top30", () => {
  const current = [
    observation("MACHINE001", 3), observation("MACHINE002", 8),
    observation("ACCESSORY1", 4), observation("UNKNOWN001", 5),
  ];
  const previous = [
    observation("MACHINE001", 14), observation("MACHINE003", 7),
    observation("ACCESSORY1", 2), observation("UNKNOWN001", 6),
  ];
  const category = {
    key: "pressure_washers", label: "高压清洗机", observations: current, previousObservations: previous,
    comparison: { ready: true, baselineDate: "2026-08-26", movers: [] },
    history: [{ marketDate: "2026-08-26", observations: previous }, { marketDate: "2026-08-27", observations: current }],
  };
  const productMetadata = [
    metadata("MACHINE001", "A", "electric_pressure_washer"),
    metadata("MACHINE002", "B", "gas_pressure_washer"),
    metadata("MACHINE003", "C", "cordless_pressure_washer"),
    metadata("ACCESSORY1", "Accessory", "surface_cleaner"),
    metadata("UNKNOWN001", null, "unknown"),
  ];

  const projected = buildAnalyticalCategory(category, productMetadata, { marketplace: "US", category: "pressure_washers", segment: "machines" });

  assert.deepEqual(current.map(({ asin }) => asin), ["MACHINE001", "MACHINE002", "ACCESSORY1", "UNKNOWN001"]);
  assert.deepEqual(projected.observations.map(({ asin }) => asin), ["MACHINE001", "MACHINE002"]);
  assert.deepEqual(projected.previousObservations.map(({ asin }) => asin), ["MACHINE001", "MACHINE003"]);
  assert.deepEqual(projected.comparison.movers.map(({ asin, change }) => [asin, change]), [["MACHINE001", 11]]);
  assert.equal(projected.comparison.entries, 1);
  assert.equal(projected.comparison.exits, 1);
  assert.deepEqual(projected.history.map(({ observations }) => observations.map(({ asin }) => asin)), [["MACHINE001", "MACHINE003"], ["MACHINE001", "MACHINE002"]]);
});

test("never carries stale raw comparison metrics into an empty machine baseline", () => {
  const current = [observation("MACHINE001", 3), observation("ACCESSORY1", 4)];
  const category = {
    key: "pressure_washers", label: "高压清洗机", observations: current,
    previousObservations: [observation("ACCESSORY1", 2)],
    comparison: { ready: true, baselineDate: "2026-08-26", averageAbsoluteMove: 17, top10Retained: 8, entries: 9, exits: 10, movers: [] },
  };
  const projected = buildAnalyticalCategory(category, [
    metadata("MACHINE001", "A", "electric_pressure_washer"), metadata("ACCESSORY1", "B", "hose"),
  ], { marketplace: "US", category: "pressure_washers", segment: "machines" });
  assert.equal(projected.comparison.ready, true);
  assert.equal(projected.comparison.averageAbsoluteMove, null);
  assert.equal(projected.comparison.top10Retained, 0);
  assert.equal(projected.comparison.top10Total, 0);
  assert.equal(projected.comparison.entries, 1);
  assert.equal(projected.comparison.exits, 0);
  assert.deepEqual(buildMarketSignals({ categoryRows: [projected] }).map(({ kind, asin }) => [kind, asin]), [["new_entry", "MACHINE001"]]);
});

test("keeps machine entry and exit events when two valid days have zero overlap", () => {
  const category = {
    key: "pressure_washers", label: "高压清洗机", observations: [observation("CURRENT001", 11)],
    previousObservations: [observation("PREVIOUS01", 9)],
    comparison: { ready: true, baselineDate: "2026-08-26", averageAbsoluteMove: 99, top10Retained: 9, entries: 0, exits: 0, movers: [] },
  };
  const projected = buildAnalyticalCategory(category, [metadata("CURRENT001", "A"), metadata("PREVIOUS01", "B")], { marketplace: "US", category: "pressure_washers", segment: "machines" });
  assert.equal(projected.comparison.ready, true);
  assert.equal(projected.comparison.averageAbsoluteMove, null);
  assert.deepEqual(buildMarketSignals({ categoryRows: [projected] }).map(({ kind }) => kind), ["exit", "new_entry"]);
});

test("reports classification coverage separately from verified machine count", () => {
  const raw = [observation("M1", 1), observation("A1", 2), observation("U1", 3), observation("N1", 4)];
  const result = buildClassificationCoverage(raw, [
    metadata("M1", "A", "electric_pressure_washer"),
    metadata("A1", "B", "hose"),
    metadata("U1", null, "unknown"),
  ]);
  assert.deepEqual(result, { total: 4, classified: 2, percent: 50, unknown: 2, verifiedMachines: 1 });
});

test("counts verified brand seats across current and previous observations", () => {
  const current = [observation("B000000001", 1), observation("B000000002", 2), observation("B000000003", 3)];
  const previous = [observation("B000000001", 2), observation("B000000004", 3)];
  const rows = buildBrandMovement({
    current,
    previous,
    metadata: [
      metadata("B000000001", "Westinghouse"),
      metadata("B000000002", "Westinghouse"),
      metadata("B000000003", null, "unknown"),
      metadata("B000000004", "MZK"),
    ],
  });

  assert.deepEqual(rows, [
    { brand: "Westinghouse", previousSeats: 1, currentSeats: 2, delta: 1, verified: true },
    { brand: "MZK", previousSeats: 1, currentSeats: 0, delta: -1, verified: true },
    { brand: "Unknown", previousSeats: 0, currentSeats: 1, delta: 1, verified: false },
  ]);
});

test("builds auditable top five brand seats with separate Others and Unknown", () => {
  const current = ["A1", "A2", "B1", "C1", "D1", "E1", "F1", "U1"].map((asin, index) => observation(asin, index + 1));
  const productMetadata = [
    metadata("A1", "Alpha"), metadata("A2", "Alpha"), metadata("B1", "Beta"), metadata("C1", "Gamma"),
    metadata("D1", "Delta"), metadata("E1", "Epsilon"), metadata("F1", "Zeta"), metadata("U1", null, "unknown"),
  ];
  const result = buildBrandStructure(current, productMetadata, 5);
  assert.deepEqual(result.rows.map(({ brand, seats, seatShare }) => [brand, seats, seatShare]), [
    ["Alpha", 2, 25], ["Beta", 1, 12.5], ["Delta", 1, 12.5], ["Epsilon", 1, 12.5], ["Gamma", 1, 12.5], ["其他", 1, 12.5], ["Unknown", 1, 12.5],
  ]);
  assert.equal(result.top3Concentration, 50);
  assert.equal(result.denominator, 8);
});

test("separates alerts from ordinary activity", () => {
  const grouped = groupMarketSignals([
    { level: "activity", asin: "A" }, { level: "watch", asin: "B" }, { level: "activity", asin: "C" }, { level: "high", asin: "D" },
  ]);
  assert.deepEqual(grouped.alerts.map(({ asin }) => asin), ["D", "B"]);
  assert.deepEqual(grouped.activity.map(({ asin }) => asin), ["A", "C"]);
});

test("computes 1D 7D and presence from valid market days only", () => {
  const history = Array.from({ length: 8 }, (_, index) => ({
    marketDate: `2026-08-${String(20 + index).padStart(2, "0")}`,
    observations: index === 2 ? [] : [observation("B000000001", 20 - index)],
  }));
  const current = history.at(-1).observations;
  const rows = buildProductRows({
    observations: current,
    comparison: { ready: true, movers: [{ ...current[0], previousRank: 14, change: 1, absoluteMove: 1 }] },
    metadata: [metadata("B000000001", "Alpha")], history,
  });
  assert.equal(rows[0].delta, 1);
  assert.equal(rows[0].sevenDayDelta, 7);
  assert.equal(rows[0].presenceDays, 7);
  assert.equal(rows[0].presenceWindowDays, 8);
  assert.equal(rows[0].presencePercent, 87.5);
});

test("returns no 7D product claim when valid-day history is insufficient", () => {
  const current = [observation("B000000001", 5)];
  const rows = buildProductRows({ observations: current, comparison: { ready: false, movers: [] }, metadata: [], history: [{ marketDate: "2026-08-27", observations: current }] });
  assert.equal(rows[0].sevenDayDelta, null);
});

test("compares equal valid-day market windows and reports a neutral direction", () => {
  const history = Array.from({ length: 14 }, (_, index) => ({
    marketDate: `2026-08-${String(10 + index).padStart(2, "0")}`,
    observations: Array.from({ length: 10 }, (_, rank) => observation(`A${rank}`, rank + 1, undefined, { price: 100 })),
  }));
  const trend = buildMarketTrend(history, 7);
  assert.equal(trend.ready, true);
  assert.equal(trend.current.validDays, 7);
  assert.equal(trend.previous.validDays, 7);
  assert.equal(trend.metrics.top10Stability.direction, "neutral");
  assert.equal(trend.metrics.medianPrice.current, 100);
});

test("does not compare a market window without an equal prior valid-day window", () => {
  assert.deepEqual(buildMarketTrend([{ marketDate: "2026-08-27", observations: [observation("A", 1)] }], 7), { ready: false, windowDays: 7 });
});

test("builds verified 7D brand seat trends without Unknown expansion claims", () => {
  const history = Array.from({ length: 8 }, (_, index) => ({ marketDate: `2026-08-${20 + index}`, observations: [observation("A", 1), ...(index === 7 ? [observation("B", 2), observation("U", 3)] : [])] }));
  const trends = buildBrandSeatTrend(history, [metadata("A", "Alpha"), metadata("B", "Beta"), metadata("U", null, "unknown")], 7);
  assert.deepEqual(trends.map(({ brand, delta, verified }) => [brand, delta, verified]), [["Beta", 1, true], ["Alpha", 0, true]]);
});

test("keeps products without metadata in the unknown brand bucket", () => {
  assert.deepEqual(buildBrandMovement({
    current: [observation("B000000001", 1)],
    previous: [],
    metadata: [],
  }), [
    { brand: "Unknown", previousSeats: 0, currentSeats: 1, delta: 1, verified: false },
  ]);
});

test("preserves verified English brand names that resemble legacy interface labels", () => {
  assert.deepEqual(buildBrandMovement({
    current: [observation("B000000001", 1)],
    previous: [],
    metadata: [metadata("B000000001", "ACTIVE")],
  }), [
    { brand: "ACTIVE", previousSeats: 0, currentSeats: 1, delta: 1, verified: true },
  ]);
});

test("combines product metadata with raw rank changes without changing rank", () => {
  const current = [observation("B000000001", 7, "Westinghouse Electric Pressure Washer with Long Amazon SEO Title")];
  const rows = buildProductRows({
    observations: current,
    comparison: {
      ready: true,
      movers: [{ ...current[0], previousRank: 18, change: 11, absoluteMove: 11 }],
    },
    metadata: [metadata("B000000001", "Westinghouse")],
  });

  assert.equal(rows[0].rank, 7);
  assert.equal(rows[0].delta, 11);
  assert.equal(rows[0].brand, "Westinghouse");
  assert.equal(rows[0].productType, "electric_pressure_washer");
  assert.equal(rows[0].isNew, false);
});

test("formats market numbers dates and long titles consistently", () => {
  assert.equal(formatCompactNumber(1200), "1.2K");
  assert.equal(formatCompactNumber(8900), "8.9K");
  assert.equal(formatCompactNumber(64621), "64.6K");
  assert.equal(formatCompactNumber(1200000), "1.2M");
  assert.equal(formatCompactNumber(414), "414");
  assert.equal(formatCompactNumber(null), "—");
  assert.equal(formatPrice(64.98), "$64.98");
  assert.equal(formatPrice(null), "—");
  assert.equal(formatDeal({ has_discount: true, discounts: [{ kind: "COUPON", amount: "$35 OFF" }] }), "$35 OFF");
  assert.equal(formatDeal({ has_discount: true, discounts: [{ kind: "COUPON", amount: "$30.00 off" }] }), "$30 OFF");
  assert.equal(formatDeal({ has_discount: false, discounts: [] }), "—");
  assert.equal(formatDeal({ price: 79.99, has_discount: true, discounts: [{ kind: "PRICE_DROP", amount: "$186.89 off" }] }), "$186.89 OFF");
  assert.equal(formatRating(4.7), "4.7 ★");
  assert.equal(formatRating(null), "—");
  assert.equal(formatPercentage(93), "93%");
  assert.equal(formatMarketDate("2026-08-26"), "Aug 26, 2026");
  assert.equal(formatCompactDate("2026-08-26"), "Aug 26");
  assert.equal(compactProductTitle("Short title"), "Short title");
  assert.equal(compactProductTitle("One two three four five six seven eight nine ten eleven twelve thirteen fourteen", 30), "One two three four five six…");
});

test("formats malformed numeric display values as missing instead of crashing", () => {
  assert.equal(formatCompactNumber("12"), "—");
  assert.equal(formatExactNumber(Number.NaN), "—");
  assert.equal(formatPrice("$12.00"), "—");
  assert.equal(formatRating(Number.POSITIVE_INFINITY), "—");
  assert.equal(formatPercentage(undefined), "—");
});

test("formats review events exactly instead of compacting evidence", () => {
  assert.equal(formatExactNumber(8949), "8,949");
  assert.equal(formatReviewChange(8949, 8977), "8,949 → 8,977  +28");
  assert.equal(formatReviewChange(8977, 8949), "8,977 → 8,949  -28");
  assert.equal(formatExactNumber(null), "—");
});

test("builds a date-scaled product timeline with gaps and canonical events", () => {
  const dates = Array.from({ length: 20 }, (_, index) => `2026-08-${String(index + 1).padStart(2, "0")}`)
    .concat(["2026-08-25", "2026-08-30"]);
  const history = dates.map((marketDate, index) => ({
    marketDate,
    observations: index === 10 ? [] : [observation("TIMELINE01", Math.min(30, index + 1), undefined, { price: 100 - index, reviews: 50 + index })],
  }));

  const timeline = buildProductRankTimeline(history, "TIMELINE01");

  assert.equal(timeline.points.length, 22);
  assert.equal(timeline.points[0].xPercent, 0);
  assert.equal(timeline.points.at(-1).xPercent, 100);
  assert.equal(timeline.points[1].xPercent < 5, true, "calendar spacing must not use equal index spacing");
  assert.equal(timeline.points[10].rank, null);
  assert.deepEqual(timeline.events.filter(({ state }) => state).map(({ state, marketDate }) => [state, marketDate]), [
    ["first_seen", "2026-08-01"],
    ["exit", "2026-08-11"],
    ["re_entry", "2026-08-12"],
  ]);
  assert.equal(timeline.segments.length, 2);
  assert.equal(timeline.axisLabels.length <= 6, true);
});

test("resolves first seen new entry re-entry exit and stable from one canonical rule", () => {
  assert.equal(resolveCanonicalEventState({ hasPreviousValidDay: false, previousInside: false, currentInside: true, historicallyInside: false }), "first_seen");
  assert.equal(resolveCanonicalEventState({ hasPreviousValidDay: true, previousInside: false, currentInside: true, historicallyInside: false }), "new_entry");
  assert.equal(resolveCanonicalEventState({ hasPreviousValidDay: true, previousInside: false, currentInside: true, historicallyInside: true }), "re_entry");
  assert.equal(resolveCanonicalEventState({ hasPreviousValidDay: true, previousInside: true, currentInside: false, historicallyInside: true }), "exit");
  assert.equal(resolveCanonicalEventState({ hasPreviousValidDay: true, previousInside: true, currentInside: true, historicallyInside: true }), "stable");
});

test("uses the canonical event state across the signal engine and product timeline", () => {
  const firstDay = { marketDate: "2026-09-05", observations: [] };
  const current = observation("CANONICAL1", 5, "Acme X1 Pressure Washer, 3000 PSI, Includes Five Nozzles");
  const currentDay = { marketDate: "2026-09-06", observations: [current] };
  const row = {
    key: "pressure_washers", label: "高压清洗机", marketDate: currentDay.marketDate,
    observations: currentDay.observations, previousObservations: firstDay.observations,
    comparison: { ready: true, baselineDate: firstDay.marketDate, movers: [] },
    history: [firstDay, currentDay],
  };

  const signal = buildMarketSignals({ categoryRows: [row] }).find(({ asin }) => asin === current.asin);
  const timelineEvent = buildProductRankTimeline(row.history, current.asin).events.find(({ state }) => state);

  assert.equal(signal?.kind, "new_entry");
  assert.equal(timelineEvent?.state, "new_entry");
  assert.equal(signal?.level, "high", "Top10 placement changes severity, not canonical event state");
});

test("emits first_seen on the first complete valid day and preserves it in the timeline", () => {
  const current = observation("FIRSTSEEN1", 15);
  const history = [{ marketDate: "2026-09-06", observations: [current] }];
  const row = {
    key: "pressure_washers", label: "高压清洗机", marketDate: "2026-09-06",
    observations: [current], previousObservations: [], history,
    comparison: { ready: false, baselineDate: null, movers: [] },
    quality: { complete: true },
  };
  assert.equal(buildMarketSignals({ categoryRows: [row] })[0]?.kind, "first_seen");
  assert.equal(buildProductRankTimeline(history, current.asin).events[0]?.state, "first_seen");
});

test("treats the final empty market day as exited rather than a stale current rank", () => {
  const timeline = buildProductRankTimeline([
    { marketDate: "2026-09-05", observations: [observation("EXITSTATUS", 5)] },
    { marketDate: "2026-09-06", observations: [] },
  ], "EXITSTATUS");
  assert.deepEqual(resolveProductTimelineStatus(timeline), {
    currentObservation: null,
    currentMarketDate: "2026-09-06",
    lastListedObservation: timeline.points[0].observation,
    lastListedMarketDate: "2026-09-05",
    delta: null,
  });
  assert.equal(timeline.events.at(-1)?.detail, "上一有效市场日 #5 → 退出 Top30");
});

test("creates one shared product display name without Amazon SEO copy", () => {
  assert.equal(productDisplayName("Acme X1 Electric Pressure Washer, 3000 PSI, Includes Five Nozzles"), "Acme X1 Electric Pressure Washer");
  assert.equal(productDisplayName("Tool Daily Foam Cannon with 1/4 Inch Quick Connector"), "Tool Daily Foam Cannon");
});

test("turns a large review drop into an anomaly instead of normal momentum", () => {
  const previous = [observation("REVANOM001", 10, undefined, { reviews: 13692 })];
  const current = [observation("REVANOM001", 9, undefined, { reviews: 8914 })];
  const row = {
    key: "pressure_washers", label: "高压清洗机", marketDate: "2026-09-06",
    observations: current, previousObservations: previous,
    comparison: { ready: true, baselineDate: "2026-09-05", movers: [{ ...current[0], previousRank: 10, change: 1, absoluteMove: 1 }] },
  };

  const reviewSignals = buildMarketSignals({ categoryRows: [row] }).filter(({ kind }) => kind.startsWith("review_"));

  assert.deepEqual(reviewSignals.map(({ kind, level, previousValue, currentValue }) => ({ kind, level, previousValue, currentValue })), [
    { kind: "review_anomaly", level: "watch", previousValue: 13692, currentValue: 8914 },
  ]);
});

test("maps category keys and activity priorities without misleading labels", () => {
  assert.deepEqual(marketContextForCategory("pressure_washers"), { category: "高压清洗机", segment: "整机" });
  assert.deepEqual(marketContextForCategory("sump_pumps"), { category: "污水泵", segment: "全部榜单" });
  assert.deepEqual(marketContextForCategory("pressure_washer_accessories"), { category: "高压清洗机配件", segment: "全部榜单" });
  assert.deepEqual(activityPriorityPresentation("high"), { label: "高优先级", tone: "high" });
  assert.deepEqual(activityPriorityPresentation("watch"), { label: "观察", tone: "medium" });
  assert.deepEqual(activityPriorityPresentation("activity"), { label: "动态", tone: "low" });
});

test("builds a complete Product Type structure without changing raw seat totals", () => {
  const current = [
    observation("TYPE000001", 1),
    observation("TYPE000002", 2),
    observation("TYPE000003", 3),
  ];
  const productMetadata = [
    metadata("TYPE000001", "Alpha", "nozzle"),
    metadata("TYPE000002", "Beta", "hose"),
    metadata("TYPE000003", null, "unknown"),
  ];
  const history = Array.from({ length: 8 }, (_, index) => ({
    marketDate: `2026-08-${String(20 + index).padStart(2, "0")}`,
    observations: index === 0 ? current.slice(0, 2) : current,
  }));

  const structure = buildProductTypeStructure(history, productMetadata, 7);

  assert.equal(structure.rows.reduce((sum, row) => sum + row.currentSeats, 0), 3);
  assert.deepEqual(structure.rows.map(({ productType, currentSeats, seatChange }) => [productType, currentSeats, seatChange]), [
    ["hose", 1, 0],
    ["nozzle", 1, 0],
    ["unknown", 1, 1],
  ]);
});

test("does not claim a Product Type trend without enough valid market days", () => {
  const structure = buildProductTypeStructure([{ marketDate: "2026-08-27", observations: [observation("TYPE000001", 1)] }], [metadata("TYPE000001", "Alpha", "nozzle")], 7);
  assert.equal(structure.trendReady, false);
  assert.equal(structure.rows[0].seatChange, null);
});

test("product type windows require their own complete endpoints and preserve every raw seat", () => {
  const current = [observation("TYPE000001", 1), observation("TYPE000002", 2)];
  const types = [metadata("TYPE000001", "Alpha", "electric_pressure_washer")];
  const history = Array.from({ length: 31 }, (_, index) => ({ marketDate: `day-${index}`, observations: index === 0 ? current.slice(0, 1) : current }));
  for (const days of [1, 7, 30]) {
    const result = buildProductTypeStructure(history, types, days);
    assert.equal(result.trendReady, true);
    assert.equal(result.rows.reduce((sum, row) => sum + row.currentSeats, 0), current.length);
    assert.equal(result.rows.find(({ productType }) => productType === "unknown").seatChange, days === 30 ? 1 : 0);
    assert.equal(buildProductTypeStructure(history.slice(-days), types, days).trendReady, false);
  }
});

test("selects only explainable low-review breakouts for further study", () => {
  const rows = [
    { ...observation("STUDY0001", 10, "Low review breakout", { reviews: 64 }), brand: "Alpha", productType: "nozzle", delta: 13, previousRank: 23, isNew: false, sevenDayDelta: null, presenceDays: 2, presenceWindowDays: 24, presencePercent: 8.3 },
    { ...observation("STUDY0002", 9, "Established mover", { reviews: 5000 }), brand: "Beta", productType: "hose", delta: 13, previousRank: 22, isNew: false, sevenDayDelta: null, presenceDays: 20, presenceWindowDays: 24, presencePercent: 83.3 },
    { ...observation("STUDY0003", 20, "Low review stable", { reviews: 20 }), brand: "Gamma", productType: "nozzle", delta: 0, previousRank: 20, isNew: false, sevenDayDelta: null, presenceDays: 10, presenceWindowDays: 24, presencePercent: 41.7 },
  ];
  assert.deepEqual(buildWorthStudyingProducts(rows).map(({ asin, reason }) => [asin, reason]), [
    ["STUDY0001", "低评论 · 快速进入 Top10"],
  ]);
});

test("summarizes current review competition with exact medians and minimum", () => {
  const result = buildReviewCompetition([
    observation("REVCOMP001", 1, undefined, { reviews: 10 }),
    observation("REVCOMP002", 2, undefined, { reviews: 30 }),
    observation("REVCOMP003", 11, undefined, { reviews: 100 }),
    observation("REVCOMP004", 12, undefined, { reviews: null }),
  ]);
  assert.deepEqual(result, { top10Median: 20, top30Median: 30, top10Minimum: 10, top10SampleSize: 2, top30SampleSize: 3 });
});
