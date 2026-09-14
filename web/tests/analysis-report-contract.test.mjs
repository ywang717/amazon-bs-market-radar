import assert from "node:assert/strict";
import test from "node:test";
import { validateAnalysisReport } from "../lib/analysis-report-contract.ts";

const validReport = {
  schemaVersion: "amazon-bs-analysis-report-v1",
  key: "daily/2026-08-24/overview.json",
  reportKind: "daily",
  marketDate: "2026-08-24",
  categoryKey: null,
  generatedAt: "2026-08-25T01:00:00Z",
  generatorVersion: "rules-v1",
  contentSha256: "a".repeat(64),
  evidence: { level: "可用", completeMarketDays: 2, sampleSize: 90, complete: true, fieldCoverage: { price: 90, rating: 90, reviews: 90 } },
  sections: [{ title: "结论摘要", statements: ["三个榜单均为完整 Top 30，可比较相邻市场日。"] }],
};

test("accepts a complete evidence-first online analysis report", () => {
  const result = validateAnalysisReport(validReport);
  assert.equal(result.ok, true);
  assert.equal(result.report.key, "daily/2026-08-24/overview.json");
});

test("rejects a trend claim when evidence is limited", () => {
  const result = validateAnalysisReport({
    ...validReport,
    evidence: { ...validReport.evidence, level: "有限", completeMarketDays: 1 },
    sections: [{ title: "周度趋势", statements: ["本周趋势稳定。"] }],
  });
  assert.equal(result.ok, false);
  assert.match(result.errors.join(" "), /趋势/);
});

test("rejects a report that contains private operational details", () => {
  const result = validateAnalysisReport({
    ...validReport,
    sections: [{ title: "结论摘要", statements: ["日志在 C:\\Users\\ASUS\\secret.log。"] }],
  });
  assert.equal(result.ok, false);
  assert.match(result.errors.join(" "), /公开/);
});
