import assert from "node:assert/strict";
import test from "node:test";
import { previousValidMarketDate, selectValidCategoryDays } from "../lib/valid-market-days.ts";

const rows = (date) => Array.from({ length: 30 }, (_, index) => ({
  market_date: date,
  category_key: "pressure_washers",
  rank: index + 1,
  asin: `B${String(index + 1).padStart(9, "0")}`,
}));
const dates = ["2026-08-18", "2026-08-19", "2026-08-20"];
const categoryDays = dates.map((market_date) => ({ market_date, category_key: "pressure_washers", complete: market_date === "2026-08-19" ? 0 : 1 }));

test("selects the previous valid day across a failed snapshot", () => {
  const observations = dates.flatMap(rows);
  const valid = selectValidCategoryDays({ categoryKey: "pressure_washers", categoryDays, observations });

  assert.deepEqual(valid, ["2026-08-18", "2026-08-20"]);
  assert.equal(previousValidMarketDate(valid, "2026-08-20"), "2026-08-18");
});

test("rejects a persisted-incomplete category with thirty otherwise valid observations", () => {
  const observations = dates.flatMap(rows);
  const valid = selectValidCategoryDays({ categoryKey: "pressure_washers", categoryDays, observations });

  assert.equal(valid.includes("2026-08-19"), false);
});
