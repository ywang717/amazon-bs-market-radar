import { compareRankings, evidenceLevel, fieldCoverage, validateCategory, type Observation } from "./analytics.ts";
import { categories, categoryByKey, type CategoryKey } from "./catalog.ts";
import type { DashboardStore, ObservationRow } from "./dashboard-store.ts";
import type { getSeedDashboard } from "./dashboard-data.ts";
import { filterAnalyticalMarket, resolveMarketDate, type MarketContext } from "./market-context.ts";
import type { ProductMetadata, ProductType } from "./product-metadata.ts";
import { previousValidMarketDate, selectValidCategoryDays } from "./valid-market-days.ts";

export type DashboardView = Omit<ReturnType<typeof getSeedDashboard>, "source" | "previousComparableDate" | "qualityHistory" | "categoryRows" | "productMetadata" | "evidence"> & {
  source: "d1" | "seed_fallback";
  latestSnapshotDate: string;
  previousComparableDate: string | null;
  qualityHistory: ReadonlyArray<{ date: string; status: "complete" | "partial"; label: string }>;
  evidence: "有限" | "可用" | "充分";
  productMetadata: ProductMetadata[];
  categoryRows: Array<ReturnType<typeof getSeedDashboard>["categoryRows"][number] & {
    marketDate: string;
    validMarketDates: string[];
    latestSnapshotObservationCount: number;
    latestSnapshotComplete: boolean;
    categoryDayPresent?: boolean;
    previousObservations?: Observation[];
    completeMarketDays?: number;
    history?: Array<{ marketDate: string; observations: Observation[] }>;
  }>;
};

export class EmptyDashboardStoreError extends Error {}

export type ProductView = {
  current: Observation;
  category: (typeof categories)[number];
  history: Array<{ marketDate: string; observation: Observation }>;
  bestRank: number;
  worstRank: number;
  daysListed: number;
  evidence: ReturnType<typeof evidenceLevel>;
};

export type AnalyticalObservation = Observation & { productType: ProductType };

async function defaultStore() {
  const { getD1, ensureSchema } = await import("./d1.ts");
  const { createD1DashboardStore } = await import("./dashboard-store.ts");
  const db = getD1();
  await ensureSchema(db);
  return createD1DashboardStore(db);
}

function observationsFor(rows: ObservationRow[], marketDate: string, categoryKey: CategoryKey): Observation[] {
  return rows
    .filter((row) => row.market_date === marketDate && row.category_key === categoryKey)
    .map((row) => ({
      rank: row.rank,
      asin: row.asin,
      title: row.title,
      url: row.url,
      price: row.price,
      rating: row.rating,
      reviews: row.reviews,
      has_discount: row.has_discount,
      discounts: row.discounts,
    }));
}

function isComplete(rows: Observation[], markedComplete: boolean) {
  return markedComplete && validateCategory(rows).complete;
}

function buildProductView(rows: ObservationRow[]): ProductView {
  const categoryIndex = new Map(categories.map((category, index) => [category.key, index]));
  const history = rows
    .toSorted((left, right) => left.market_date.localeCompare(right.market_date)
      || categoryIndex.get(left.category_key)! - categoryIndex.get(right.category_key)!
      || left.rank - right.rank)
    .map((row) => ({
      marketDate: row.market_date,
      observation: {
        rank: row.rank,
        asin: row.asin,
        title: row.title,
        url: row.url,
        price: row.price,
        rating: row.rating,
        reviews: row.reviews,
        has_discount: row.has_discount,
        discounts: row.discounts,
      },
    }));
  const latestMarketDate = history.at(-1)!.marketDate;
  const currentRow = rows
    .filter((row) => row.market_date === latestMarketDate)
    .toSorted((left, right) => categoryIndex.get(left.category_key)! - categoryIndex.get(right.category_key)! || left.rank - right.rank)
    .at(0)!;
  const daysListed = new Set(history.map(({ marketDate }) => marketDate)).size;
  return {
    current: {
      rank: currentRow.rank,
      asin: currentRow.asin,
      title: currentRow.title,
      url: currentRow.url,
      price: currentRow.price,
      rating: currentRow.rating,
      reviews: currentRow.reviews,
      has_discount: currentRow.has_discount,
      discounts: currentRow.discounts,
    },
    category: categoryByKey[currentRow.category_key],
    history,
    bestRank: Math.min(...history.map(({ observation }) => observation.rank)),
    worstRank: Math.max(...history.map(({ observation }) => observation.rank)),
    daysListed,
    evidence: evidenceLevel(daysListed),
  };
}

export async function loadVerifiedDashboardFromStore(store: DashboardStore, options: { marketDate?: string; preferLatestSnapshot?: boolean } = {}): Promise<DashboardView> {
  const [snapshots, categoryDays, observations] = await Promise.all([
    store.listSnapshots(),
    store.listCategoryDays(),
    store.listObservations(),
  ]);
  let productMetadata: ProductMetadata[] = [];
  let metadataAvailable = true;
  try {
    productMetadata = await store.listProductMetadata();
  } catch {
    metadataAvailable = false;
  }
  if (snapshots.length === 0) throw new EmptyDashboardStoreError("Dashboard store is empty");

  const snapshot = snapshots.toSorted((left, right) => left.market_date.localeCompare(right.market_date)).at(-1)!;
  const categoryDayFor = (marketDate: string, categoryKey: CategoryKey) =>
    categoryDays.find((day) => day.market_date === marketDate && day.category_key === categoryKey);
  const completeOn = (marketDate: string, categoryKey: CategoryKey) => {
    const day = categoryDayFor(marketDate, categoryKey);
    return Boolean(day && isComplete(observationsFor(observations, marketDate, categoryKey), day.complete === 1));
  };
  const validDatesByCategory = new Map(categories.map((category) => [
    category.key,
    selectValidCategoryDays({ categoryKey: category.key, categoryDays, observations }),
  ]));

  const orderedSnapshotDates = snapshots
    .map(({ market_date }) => market_date)
    .toSorted((left, right) => left.localeCompare(right));
  const categoryRows = categories.map((category) => {
    const validDates = validDatesByCategory.get(category.key)!;
    const marketDate = options.marketDate
      ? resolveMarketDate(options.marketDate, validDates).marketDate ?? snapshot.market_date
      : options.preferLatestSnapshot ? snapshot.market_date : validDates.at(-1) ?? snapshot.market_date;
    const current = observationsFor(observations, marketDate, category.key);
    const latestSnapshotObservations = observationsFor(observations, snapshot.market_date, category.key);
    const latestSnapshotDay = categoryDayFor(snapshot.market_date, category.key);
    const latestSnapshotComplete = Boolean(latestSnapshotDay && isComplete(latestSnapshotObservations, latestSnapshotDay.complete === 1));
    const categoryDayPresent = categoryDayFor(marketDate, category.key) !== undefined;
    const quality = validateCategory(current);
    const complete = validDates.includes(marketDate);
    const categoryPreviousDate = complete ? previousValidMarketDate(validDates, marketDate) : null;
    const previous = categoryPreviousDate ? observationsFor(observations, categoryPreviousDate, category.key) : [];
    const history = orderedSnapshotDates
      .filter((historyDate) => validDates.includes(historyDate) && historyDate <= marketDate)
      .map((marketDate) => ({ marketDate, observations: observationsFor(observations, marketDate, category.key) }));
    return {
      ...category,
      marketDate,
      validMarketDates: validDates,
      latestSnapshotObservationCount: latestSnapshotObservations.length,
      latestSnapshotComplete,
      categoryDayPresent,
      observations: current,
      quality: { ...quality, complete },
      leader: current.find(({ rank }) => rank === 1) ?? null,
      priceCoverage: fieldCoverage(current, "price"),
      ratingCoverage: fieldCoverage(current, "rating"),
      reviewsCoverage: fieldCoverage(current, "reviews"),
      comparison: { ...compareRankings(previous, current), baselineDate: categoryPreviousDate },
      previousObservations: previous,
      completeMarketDays: history.length,
      history,
    };
  });
  const baselineDates = categoryRows.map((row) => row.comparison.baselineDate);
  const previousComparableDate = baselineDates.length > 0
    && baselineDates.every((date) => date !== null && date === baselineDates[0])
    ? baselineDates[0]
    : null;

  const qualityHistory = snapshots.map(({ market_date }) => {
    const complete = categories.every((category) => completeOn(market_date, category.key));
    return {
      date: market_date,
      status: complete ? "complete" as const : "partial" as const,
      label: complete ? "完整" : "不完整",
    };
  });
  const completeMarketDays = qualityHistory.filter(({ status }) => status === "complete").length;
  return {
    marketDate: snapshot.market_date,
    latestSnapshotDate: snapshot.market_date,
    observedAt: (() => { const d = new Date(snapshot.observed_at); return Number.isNaN(d.getTime()) ? snapshot.observed_at : `${new Intl.DateTimeFormat("zh-CN", { timeZone: "America/Los_Angeles", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false }).format(d)} (Pacific Time)`; })(),
    categoryRows,
    qualityHistory,
    totalObservations: categoryRows.reduce((sum, row) => sum + row.observations.length, 0),
    completeCategories: categoryRows.filter((row) => row.quality.complete).length,
    completeMarketDays,
    evidence: evidenceLevel(completeMarketDays),
    productMetadata,
    metadataAvailable,
    source: "d1",
    previousComparableDate,
  };
}

export async function loadLiveDashboard(options: { store?: DashboardStore; marketDate?: string; preferLatestSnapshot?: boolean } = {}): Promise<DashboardView> {
  try {
    return await loadVerifiedDashboardFromStore(options.store ?? await defaultStore(), {
      marketDate: options.marketDate,
      preferLatestSnapshot: options.preferLatestSnapshot,
    });
  } catch {
    const { getSeedDashboard } = await import("./dashboard-data.ts");
    const seed = getSeedDashboard(options.marketDate);
    return {
      ...seed,
      evidence: seed.evidence as DashboardView["evidence"],
      latestSnapshotDate: seed.marketDate,
      categoryRows: seed.categoryRows.map((row) => ({
        ...row,
        marketDate: seed.marketDate,
        validMarketDates: row.history.map(({ marketDate }) => marketDate),
        latestSnapshotObservationCount: row.observations.length,
        latestSnapshotComplete: row.quality.complete,
        completeMarketDays: row.history.length,
      })),
    };
  }
}

export async function loadAnalyticalOverview(context: MarketContext, options: { store?: DashboardStore; marketDate?: string } = {}) {
  const store = options.store ?? await defaultStore();
  const [dashboard, metadata] = await Promise.all([
    loadVerifiedDashboardFromStore(store, { marketDate: options.marketDate }),
    store.listProductMetadata(),
  ]);
  const selectedCategory = dashboard.categoryRows.find(({ key }) => key === context.category)!;
  if (!selectedCategory.categoryDayPresent || !selectedCategory.quality.complete) {
    throw new EmptyDashboardStoreError("Selected category day is unavailable for analysis");
  }
  const rawObservations = selectedCategory.observations;
  const metadataByAsin = new Map(metadata.map((row) => [row.asin, row]));
  const enriched: AnalyticalObservation[] = rawObservations.map((row) => ({
    ...row,
    productType: metadataByAsin.get(row.asin)?.productType ?? "unknown",
  }));
  return {
    dashboard,
    rawObservationCount: rawObservations.length,
    analyticalObservations: filterAnalyticalMarket(enriched, metadata, context),
  };
}

export async function loadLiveProduct(asin: string, options: { store?: DashboardStore; context?: MarketContext; marketDate?: string } = {}) {
  try {
    const store = options.store ?? await defaultStore();
    const [snapshots, categoryDays, allObservations, metadata] = await Promise.all([
      store.listSnapshots(),
      store.listCategoryDays(),
      store.listObservations(),
      store.listProductMetadata(),
    ]);
    if (snapshots.length === 0) throw new EmptyDashboardStoreError("Dashboard store is empty");
    const validDates = new Set(categories.flatMap((category) =>
      selectValidCategoryDays({ categoryKey: category.key, categoryDays, observations: allObservations })
        .map((marketDate) => `${marketDate}|${category.key}`),
    ));
    const contextValidDates = options.context
      ? selectValidCategoryDays({ categoryKey: options.context.category, categoryDays, observations: allObservations })
      : [];
    const effectiveMarketDate = options.context ? resolveMarketDate(options.marketDate, contextValidDates).marketDate : null;
    if (options.context?.segment !== undefined && options.context.segment !== "all"
      && filterAnalyticalMarket([{ asin }], metadata, options.context).length === 0) {
      return { status: "not_found" } as const;
    }
    const rows = allObservations.filter((row) => row.asin === asin
      && (!options.context || row.category_key === options.context.category)
      && (!effectiveMarketDate || row.market_date <= effectiveMarketDate)
      && validDates.has(`${row.market_date}|${row.category_key}`));
    if (rows.length === 0) return { status: "not_found" } as const;
    return { status: "found", source: "d1" as const, product: buildProductView(rows) } as const;
  } catch {
    const { getProductHistory } = await import("./dashboard-data.ts");
    const seedRows = getProductHistory(asin)
      .filter(({ category }) => !options.context || category.key === options.context.category)
      .filter(({ marketDate }) => !options.marketDate || marketDate <= options.marketDate)
      .map(({ marketDate, category, observation }) => ({
        ...observation,
        market_date: marketDate,
        category_key: category.key,
      }));
    return seedRows.length
      ? { status: "found", source: "seed_fallback" as const, product: buildProductView(seedRows) } as const
      : { status: "not_found" } as const;
  }
}
