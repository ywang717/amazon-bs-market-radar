import assert from "node:assert/strict";
import test from "node:test";
import { buildLiveAnalysisReport } from "../lib/live-analysis.ts";

function dashboard({ complete = false, days = 1 } = {}) {
  const row = {
    key: "pressure_washers", label: "高压清洗机", quality: { complete }, observations: complete ? Array.from({ length: 30 }, (_, index) => ({ rank: index + 1 })) : [{ rank: 1 }],
    priceCoverage: { percent: 100 }, ratingCoverage: { percent: 100 }, reviewsCoverage: { percent: 100 }, comparison: { ready: complete, largeMoves: complete ? 2 : null, entries: complete ? 1 : null, exits: complete ? 1 : null },
  };
  return { marketDate: "2026-08-24", observedAt: "2026-08-25T01:00:00Z", completeMarketDays: days, evidence: days >= 5 ? "充分" : days >= 2 ? "可用" : "有限", categoryRows: [row, { ...row, key: "sump_pumps", label: "污水泵" }, { ...row, key: "pressure_washer_accessories", label: "高压清洗机配件" }] };
}

test("keeps an incomplete live analysis to a quality disclosure", async () => {
  const report = await buildLiveAnalysisReport(dashboard(), { reportKind: "daily", categoryKey: null });
  assert.equal(report.evidence.level, "有限");
  assert.doesNotMatch(report.sections.flatMap((section) => [section.title, ...section.statements]).join(" "), /趋势|关联|留存/);
  assert.match(report.sections.flatMap((section) => section.statements).join(" "), /暂不下结论|不完整/);
});

test("exposes a weekly descriptive trend only after five complete market days", async () => {
  const report = await buildLiveAnalysisReport(dashboard({ complete: true, days: 5 }), { reportKind: "weekly", categoryKey: "pressure_washers" });
  assert.equal(report.evidence.level, "充分");
  assert.match(report.sections.map((section) => section.title).join(" "), /周度趋势/);
  assert.match(report.sections.flatMap((section) => section.statements).join(" "), /非因果/);
});
