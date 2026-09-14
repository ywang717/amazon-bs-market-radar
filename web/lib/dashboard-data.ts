import { categories, type CategoryKey } from "./catalog.ts";
import { compareRankings, evidenceLevel, fieldCoverage, validateCategory } from "./analytics.ts";
import { qualityHistory, verifiedHistory, verifiedSeed } from "./seed-data.ts";

export function getSeedDashboard(requestedMarketDate?: string) {
  const selectedIndex = requestedMarketDate
    ? Math.max(0, verifiedHistory.findLastIndex(({ market_date }) => market_date <= requestedMarketDate))
    : verifiedHistory.length - 1;
  const selectedSnapshot = verifiedHistory[selectedIndex] ?? verifiedSeed;
  const selectedHistory = verifiedHistory.slice(0, selectedIndex + 1);
  const baselineSnapshot = selectedHistory.at(-2);
  const baselineDate: string | null = baselineSnapshot?.market_date ?? null;
  const categoryRows = categories.map((category) => {
    const observations = selectedSnapshot[category.key] ?? [];
    const history = selectedHistory.map((snapshot) => ({
      marketDate: snapshot.market_date,
      observations: snapshot[category.key] ?? [],
    }));
    return {
      ...category,
      observations,
      quality: validateCategory(observations),
      leader: observations.find(({ rank }) => rank === 1) ?? null,
      priceCoverage: fieldCoverage(observations, "price"),
      ratingCoverage: fieldCoverage(observations, "rating"),
      reviewsCoverage: fieldCoverage(observations, "reviews"),
      comparison: { ...compareRankings(baselineSnapshot?.[category.key] ?? [], observations), baselineDate },
      previousObservations: baselineSnapshot?.[category.key] ?? [],
      history,
    };
  });
  return {
    marketDate: selectedSnapshot.market_date,
    observedAt: (() => { const d = new Date(selectedSnapshot.observed_at); return Number.isNaN(d.getTime()) ? selectedSnapshot.observed_at : `${new Intl.DateTimeFormat("zh-CN", { timeZone: "America/Los_Angeles", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false }).format(d)} (Pacific Time)`; })(),
    categoryRows,
    qualityHistory,
    totalObservations: categoryRows.reduce((sum, row) => sum + row.observations.length, 0),
    completeCategories: categoryRows.filter((row) => row.quality.complete).length,
    completeMarketDays: selectedHistory.length,
    evidence: evidenceLevel(selectedHistory.length),
    productMetadata: [],
    metadataAvailable: true,
    source: "seed_fallback" as const,
    previousComparableDate: baselineDate,
  };
}

export function getProduct(asin: string) {
  for (const category of categories) {
    const observation = verifiedSeed[category.key as CategoryKey]?.find((row) => row.asin === asin);
    if (observation) return { observation, category };
  }
  return null;
}

export function getProductHistory(asin: string) {
  const rows = [];
  for (const snapshot of verifiedHistory) for (const category of categories) {
    const observation = snapshot[category.key]?.find((row) => row.asin === asin);
    if (observation) rows.push({ marketDate: snapshot.market_date, category, observation });
  }
  return rows;
}
