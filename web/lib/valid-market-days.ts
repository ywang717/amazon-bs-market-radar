import { validateCategory, type Observation } from "./analytics.ts";
import type { CategoryDayRow, ObservationRow } from "./dashboard-store.ts";
import type { CategoryKey } from "./catalog.ts";

export function selectValidCategoryDays(input: {
  categoryKey: CategoryKey;
  categoryDays: Array<Pick<CategoryDayRow, "market_date" | "category_key" | "complete">>;
  observations: Array<Pick<ObservationRow, "market_date" | "category_key" | "rank" | "asin">>;
}): string[] {
  const dates = new Set(
    input.categoryDays
      .filter((day) => day.category_key === input.categoryKey && day.complete === 1)
      .map((day) => day.market_date),
  );
  return [...dates]
    .filter((marketDate) => {
      const observations = input.observations
        .filter((row) => row.market_date === marketDate && row.category_key === input.categoryKey)
        .map((row) => ({ rank: row.rank, asin: row.asin } as Observation));
      return validateCategory(observations).complete;
    })
    .toSorted((left, right) => left.localeCompare(right));
}

export function previousValidMarketDate(validDates: string[], currentMarketDate: string): string | null {
  return validDates
    .filter((marketDate) => marketDate < currentMarketDate)
    .toSorted((left, right) => right.localeCompare(left))[0] ?? null;
}
