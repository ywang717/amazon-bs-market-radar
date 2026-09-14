import assert from "node:assert/strict";
import test from "node:test";
import { validateSellerIntelligenceReport } from "../lib/seller-intelligence-contract.ts";

const alert = {
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
};

test("accepts an auditable seller alert", () => {
  const result = validateSellerIntelligenceReport(alert);
  assert.equal(result.ok, true);
  assert.equal(result.report.profile, "seller_alert");
});

test("accepts a seller alert overview with null category scope", () => {
  const result = validateSellerIntelligenceReport({
    ...alert,
    key: "seller-alert/daily/2026-08-24/overview.json",
    categoryKey: null,
    sections: [{ title: "经营预警总览", statements: ["三个榜单仅输出待核查的公开变化。"] }],
  });
  assert.equal(result.ok, true);
  assert.equal(result.report.categoryKey, null);
});

test("rejects weekly trend below five complete days", () => {
  const result = validateSellerIntelligenceReport({
    ...alert,
    key: "competition-strategy/weekly/2026-08-24/pressure_washers.json",
    reportKind: "weekly",
    profile: "competition_strategy",
    evidence: { ...alert.evidence, completeMarketDays: 4 },
    sections: [{ title: "周度趋势", statements: ["趋势稳定"] }],
  });
  assert.equal(result.ok, false);
  assert.match(result.errors.join(" "), /趋势|策略/);
});

test("rejects a report that includes private operational text", () => {
  const result = validateSellerIntelligenceReport({
    ...alert,
    signals: [
      {
        ...alert.signals[0],
        evidence: ["导出文件位于 C:\\Users\\ASUS\\secret\\seller.csv"],
      },
    ],
  });
  assert.equal(result.ok, false);
  assert.match(result.errors.join(" "), /公开/);
});

test("rejects mismatched key and profile pairing", () => {
  const result = validateSellerIntelligenceReport({
    ...alert,
    key: "competition-strategy/weekly/2026-08-24/pressure_washers.json",
  });
  assert.equal(result.ok, false);
  assert.match(result.errors.join(" "), /报告键/);
});

test("rejects categoryKey that does not exactly match key scope", () => {
  const scopedCategoryResult = validateSellerIntelligenceReport({
    ...alert,
    categoryKey: null,
  });
  assert.equal(scopedCategoryResult.ok, false);
  assert.match(scopedCategoryResult.errors.join(" "), /范围一致/);

  const overviewResult = validateSellerIntelligenceReport({
    ...alert,
    key: "competition-strategy/weekly/2026-08-24/overview.json",
    reportKind: "weekly",
    profile: "competition_strategy",
    categoryKey: "pressure_washers",
    sections: [{ title: "竞争摘要", statements: ["本周仅做描述性整理。"] }],
  });
  assert.equal(overviewResult.ok, false);
  assert.match(overviewResult.errors.join(" "), /范围一致/);

  const sellerOverviewMismatch = validateSellerIntelligenceReport({
    ...alert,
    key: "seller-alert/daily/2026-08-24/overview.json",
    categoryKey: "pressure_washers",
    sections: [{ title: "经营预警总览", statements: ["三个榜单仅输出待核查的公开变化。"] }],
  });
  assert.equal(sellerOverviewMismatch.ok, false);
  assert.match(sellerOverviewMismatch.errors.join(" "), /范围一致/);

  const sellerScopedNullMismatch = validateSellerIntelligenceReport({
    ...alert,
    key: "seller-alert/daily/2026-08-24/pressure_washers.json",
    categoryKey: null,
  });
  assert.equal(sellerScopedNullMismatch.ok, false);
  assert.match(sellerScopedNullMismatch.errors.join(" "), /范围一致/);
});

test("rejects empty signal evidence", () => {
  const result = validateSellerIntelligenceReport({
    ...alert,
    signals: [{ ...alert.signals[0], evidence: [] }],
  });
  assert.equal(result.ok, false);
  assert.match(result.errors.join(" "), /信号/);
});

test("rejects database backup task and internal-error leakage", () => {
  const result = validateSellerIntelligenceReport({
    ...alert,
    signals: [
      {
        ...alert.signals[0],
        checks: ["database backup task failed after internal error"],
      },
    ],
  });
  assert.equal(result.ok, false);
  assert.match(result.errors.join(" "), /公开/);
});

test("rejects key dates and daily signal semantics that drift from the audited rules", () => {
  const invalidReports = [
    { ...alert, key: "seller-alert/daily/2026-08-25/pressure_washers.json" },
    { ...alert, signals: [{ ...alert.signals[0], currentRank: 8, previousRank: 21 }] },
    { ...alert, signals: [{ ...alert.signals[0], priority: "medium", currentRank: 4, previousRank: 26 }] },
    { ...alert, signals: [{ ...alert.signals[0], kind: "top10_entry", currentRank: 11, previousRank: 9 }] },
    { ...alert, signals: [{ ...alert.signals[0], kind: "top30_entry", currentRank: 4, previousRank: 26 }] },
    { ...alert, evidence: { ...alert.evidence, complete: false } },
    {
      ...alert,
      signals: [{
        ...alert.signals[0],
        kind: "discount_change",
        currentRank: 4,
        previousRank: 26,
        discountBefore: null,
        discountAfter: "Coupon 10%",
      }],
    },
  ];

  for (const invalidReport of invalidReports) {
    assert.equal(validateSellerIntelligenceReport(invalidReport).ok, false);
  }
});

test("accepts verified brand seat signals and rejects Unknown brand claims", () => {
  const brandAlert = {
    ...alert,
    signals: [{
      priority: "high",
      kind: "brand_expansion",
      asin: null,
      brand: "Alpha",
      currentRank: null,
      previousRank: null,
      currentValue: 4,
      previousValue: 2,
      checks: ["核查品牌归一化与 Top30 席位"],
      evidence: ["Alpha · 2 席 → 4 席"],
    }],
  };
  assert.equal(validateSellerIntelligenceReport(brandAlert).ok, true);
  assert.equal(validateSellerIntelligenceReport({ ...brandAlert, signals: [{ ...brandAlert.signals[0], brand: "Unknown" }] }).ok, false);
});

test("accepts only canonical High Watch Activity seller signal severity", () => {
  const watch = { ...alert, signals: [{ ...alert.signals[0], priority: "watch", kind: "rank_move", currentRank: 14, previousRank: 25 }] };
  const activity = { ...alert, signals: [{ ...alert.signals[0], priority: "activity", kind: "top30_entry", currentRank: 24, previousRank: null }] };
  const legacy = { ...watch, signals: [{ ...watch.signals[0], priority: "medium" }] };
  assert.equal(validateSellerIntelligenceReport(watch).ok, true);
  assert.equal(validateSellerIntelligenceReport(activity).ok, true);
  assert.equal(validateSellerIntelligenceReport(legacy).ok, false);
});

test("requires structured strategy facts on every weekly competition report", () => {
  const weekly = {
    ...alert,
    key: "competition-strategy/weekly/2026-08-24/pressure_washers.json",
    reportKind: "weekly",
    profile: "competition_strategy",
    evidence: {
      ...alert.evidence,
      fieldCoverage: { ...alert.evidence.fieldCoverage, specs: 100 },
    },
    signals: [],
    sections: [{ title: "竞争策略", statements: ["基于五个完整市场日提供描述性观察。"] }],
  };

  const missing = validateSellerIntelligenceReport(weekly);
  assert.equal(missing.ok, false);
  assert.match(missing.errors.join(" "), /策略/);

  const valid = validateSellerIntelligenceReport({
    ...weekly,
    strategy: {
      priceBands: [{ lower: 100, upper: 200, sampleSize: 30 }],
      rankingConcentration: { top10RankWeightPercent: 50, top10Slots: 10 },
      topStability: { retainedTop10: 8, entries: 2, exits: 2, baselineDate: "2026-08-23" },
      competitorPool: [{ asin: "B000000001", title: "Example", daysPresent: 5, top10Appearances: 3, latestRank: 4, maxAbsoluteMovement: 8, priority: "medium" }],
      specificationTrend: { coverage: 100, observedFields: ["压力"] },
    },
  });
  assert.equal(valid.ok, true);
});

test("rejects populated strategy facts when weekly evidence is not eligible", () => {
  const populatedStrategy = {
    priceBands: [{ lower: 100, upper: 200, sampleSize: 30 }],
    rankingConcentration: { top10RankWeightPercent: 50, top10Slots: 10 },
    topStability: { retainedTop10: 8, entries: 2, exits: 2, baselineDate: "2026-08-23" },
    competitorPool: [{ asin: "B000000001", title: "Example", daysPresent: 5, top10Appearances: 3, latestRank: 4, maxAbsoluteMovement: 8, priority: "medium" }],
    specificationTrend: { coverage: 100, observedFields: ["压力"] },
  };
  const weekly = {
    ...alert,
    key: "competition-strategy/weekly/2026-08-24/pressure_washers.json",
    reportKind: "weekly",
    profile: "competition_strategy",
    signals: [],
    sections: [{ title: "证据说明", statements: ["当前仅展示可验证事实。"] }],
    evidence: {
      ...alert.evidence,
      fieldCoverage: { ...alert.evidence.fieldCoverage, specs: 100 },
    },
    strategy: populatedStrategy,
  };

  const invalidReports = [
    { ...weekly, categoryKey: null, key: "competition-strategy/weekly/2026-08-24/overview.json" },
    { ...weekly, evidence: { ...weekly.evidence, complete: false } },
    { ...weekly, evidence: { ...weekly.evidence, completeMarketDays: 4 } },
  ];

  for (const invalidReport of invalidReports) {
    const result = validateSellerIntelligenceReport(invalidReport);
    assert.equal(result.ok, false);
    assert.match(result.errors.join(" "), /策略/);
  }
});

test("rejects strategy facts that bypass coverage gates or violate fact bounds", () => {
  const strategy = {
    priceBands: [{ lower: 100, upper: 200, sampleSize: 30 }],
    rankingConcentration: { top10RankWeightPercent: 50, top10Slots: 10 },
    topStability: { retainedTop10: 8, entries: 2, exits: 2, baselineDate: "2026-08-23" },
    competitorPool: [{ asin: "B000000001", title: "Example", daysPresent: 5, top10Appearances: 3, latestRank: 4, maxAbsoluteMovement: 8, priority: "medium" }],
    specificationTrend: { coverage: 100, observedFields: ["压力"] },
  };
  const weekly = {
    ...alert,
    key: "competition-strategy/weekly/2026-08-24/pressure_washers.json",
    reportKind: "weekly",
    profile: "competition_strategy",
    signals: [],
    sections: [{ title: "证据说明", statements: ["当前仅展示可验证事实。"] }],
    evidence: {
      ...alert.evidence,
      fieldCoverage: { ...alert.evidence.fieldCoverage, specs: 100 },
    },
    strategy,
  };
  const invalidReports = [
    { ...weekly, evidence: { ...weekly.evidence, fieldCoverage: { ...weekly.evidence.fieldCoverage, price: 79 } } },
    { ...weekly, evidence: { ...weekly.evidence, fieldCoverage: { ...weekly.evidence.fieldCoverage, specs: 79 } } },
    { ...weekly, strategy: { ...strategy, priceBands: [] } },
    { ...weekly, strategy: { ...strategy, rankingConcentration: { top10RankWeightPercent: 50, top10Slots: 9 } } },
    { ...weekly, strategy: { ...strategy, topStability: { retainedTop10: -1, entries: 11, exits: 11, baselineDate: "2026-08-23" } } },
    { ...weekly, strategy: { ...strategy, competitorPool: [{ ...strategy.competitorPool[0], latestRank: 0 }] } },
    { ...weekly, strategy: { ...strategy, competitorPool: [{ ...strategy.competitorPool[0], top10Appearances: 6 }] } },
  ];

  for (const invalidReport of invalidReports) {
    const result = validateSellerIntelligenceReport(invalidReport);
    assert.equal(result.ok, false);
    assert.match(result.errors.join(" "), /策略/);
  }
});

test("rejects malformed weekly field coverage without throwing", () => {
  const report = {
    ...alert,
    key: "competition-strategy/weekly/2026-08-24/pressure_washers.json",
    reportKind: "weekly",
    profile: "competition_strategy",
    signals: [],
    sections: [{ title: "证据说明", statements: ["当前仅展示可验证事实。"] }],
    evidence: { ...alert.evidence, completeMarketDays: 5, fieldCoverage: null },
    strategy: {
      priceBands: [{ lower: 100, upper: 200, sampleSize: 30 }],
      rankingConcentration: { top10RankWeightPercent: 50, top10Slots: 10 },
      topStability: { retainedTop10: 8, entries: 2, exits: 2, baselineDate: "2026-08-23" },
      competitorPool: [{ asin: "B000000001", title: "Example", daysPresent: 5, top10Appearances: 3, latestRank: 4, maxAbsoluteMovement: 8, priority: "medium" }],
      specificationTrend: { coverage: 100, observedFields: ["压力"] },
    },
  };

  let result;
  assert.doesNotThrow(() => {
    result = validateSellerIntelligenceReport(report);
  });
  assert.equal(result.ok, false);
  assert.match(result.errors.join(" "), /覆盖率|策略/);
});
