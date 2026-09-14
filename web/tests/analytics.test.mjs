import assert from "node:assert/strict";
import test from "node:test";
import {
  compareRankings,
  evidenceLevel,
  fieldCoverage,
  validateCategory,
} from "../lib/analytics.ts";

const item = (rank, asin, extra = {}) => ({
  rank,
  asin,
  title: `Product ${asin}`,
  url: `https://www.amazon.com/dp/${asin}`,
  price: 20,
  rating: 4.5,
  reviews: 100,
  ...extra,
});
const complete = (prefix = "A") =>
  Array.from({ length: 30 }, (_, index) => item(index + 1, `${prefix}${String(index + 1).padStart(9, "0")}`));

test("rejects a Top 30 category with a missing global rank", () => {
  const observations = complete().filter((row) => row.rank !== 17);
  const quality = validateCategory(observations);

  assert.equal(quality.complete, false);
  assert.deepEqual(quality.missingRanks, [17]);
  assert.equal(quality.observationCount, 29);
});

test("compares rankings only when both market days are complete", () => {
  const previous = complete();
  const current = complete();
  [current[0], current[11]] = [current[11], current[0]];
  current.forEach((row, index) => (row.rank = index + 1));

  const comparison = compareRankings(previous, current);

  assert.equal(comparison.ready, true);
  assert.equal(comparison.top10Retained, 9);
  assert.equal(comparison.largeMoves, 2);
  assert.equal(comparison.highPriorityMoves, 0);
  assert.equal(comparison.entries, 0);
  assert.equal(comparison.exits, 0);
  assert.equal(comparison.maxAbsoluteMove, 11);
  assert.deepEqual(comparison.movementBands, { stable: 28, moderate: 0, notable: 0, large: 2 });
});

test("suppresses change claims when either category is incomplete", () => {
  const comparison = compareRankings(complete(), complete().slice(0, 29));

  assert.equal(comparison.ready, false);
  assert.equal(comparison.reason, "需要相邻两个完整 Top 30 市场日");
  assert.equal(comparison.largeMoves, null);
});

test("assigns evidence levels from complete market-day count", () => {
  assert.equal(evidenceLevel(1), "有限");
  assert.equal(evidenceLevel(2), "可用");
  assert.equal(evidenceLevel(4), "可用");
  assert.equal(evidenceLevel(5), "充分");
});

test("pauses field analysis below eighty percent coverage", () => {
  const rows = complete().map((row, index) => ({ ...row, price: index < 23 ? 20 : null }));
  const coverage = fieldCoverage(rows, "price");

  assert.equal(coverage.present, 23);
  assert.equal(coverage.total, 30);
  assert.equal(coverage.percent, 76.7);
  assert.equal(coverage.ready, false);
});
