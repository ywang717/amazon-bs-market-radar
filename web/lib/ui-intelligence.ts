import type { Observation } from "./analytics.ts";
import type { ProductMetadata, ProductType } from "./product-metadata.ts";
import { filterAnalyticalMarket, isMachineProductType, type MarketContext } from "./market-context.ts";
import { productionCategoryRegistry } from "./category-registry.ts";

type RankingMover = Observation & {
  previousRank: number;
  change: number;
  absoluteMove: number;
};

type RankingComparison = {
  ready: boolean;
  baselineDate?: string | null;
  averageAbsoluteMove?: number | null;
  top10Retained?: number | null;
  top10Total?: number | null;
  entries?: number | null;
  exits?: number | null;
  movers?: RankingMover[];
};

function analyticalComparison(previous: Observation[], current: Observation[], source: RankingComparison): RankingComparison {
  const unavailable = {
    ready: false,
    baselineDate: source.baselineDate ?? null,
    averageAbsoluteMove: null,
    top10Retained: null,
    top10Total: null,
    entries: null,
    exits: null,
    movers: [],
  };
  if (!source.ready) return unavailable;
  const previousByAsin = new Map(previous.map((row) => [row.asin, row]));
  const currentByAsin = new Map(current.map((row) => [row.asin, row]));
  const movers = current.filter(({ asin }) => previousByAsin.has(asin)).map((row) => {
    const previousRank = previousByAsin.get(row.asin)!.rank;
    return { ...row, previousRank, change: previousRank - row.rank, absoluteMove: Math.abs(previousRank - row.rank) };
  }).toSorted((left, right) => right.absoluteMove - left.absoluteMove || left.rank - right.rank);
  const previousTop10 = new Set(previous.filter(({ rank }) => rank <= 10).map(({ asin }) => asin));
  const currentTop10 = new Set(current.filter(({ rank }) => rank <= 10).map(({ asin }) => asin));
  const averageAbsoluteMove = movers.length ? movers.reduce((sum, row) => sum + row.absoluteMove, 0) / movers.length : null;
  return {
    ready: true,
    baselineDate: source.baselineDate ?? null,
    averageAbsoluteMove: averageAbsoluteMove === null ? null : Math.round(averageAbsoluteMove * 10) / 10,
    top10Retained: [...currentTop10].filter((asin) => previousTop10.has(asin)).length,
    top10Total: previousTop10.size,
    entries: current.filter(({ asin }) => !previousByAsin.has(asin)).length,
    exits: previous.filter(({ asin }) => !currentByAsin.has(asin)).length,
    movers,
  };
}

export function buildAnalyticalCategory<T extends IntelligenceCategoryRow & { history?: Array<{ marketDate: string; observations: Observation[] }> }>(
  category: T,
  metadata: ProductMetadata[],
  context: MarketContext,
) {
  const observations = filterAnalyticalMarket(category.observations, metadata, context);
  const previousObservations = filterAnalyticalMarket(category.previousObservations ?? [], metadata, context);
  return {
    ...category,
    observations,
    previousObservations,
    comparison: analyticalComparison(previousObservations, observations, category.comparison),
    history: category.history?.map((day) => ({ ...day, observations: filterAnalyticalMarket(day.observations, metadata, context) })),
  };
}

export function buildClassificationCoverage(observations: Observation[], metadata: ProductMetadata[]) {
  const typeByAsin = new Map(metadata.map(({ asin, productType }) => [asin, productType]));
  const productTypes = observations.map(({ asin }) => typeByAsin.get(asin) ?? "unknown");
  const classified = productTypes.filter((type) => type !== "unknown").length;
  return {
    total: observations.length,
    classified,
    percent: observations.length ? Math.round(classified / observations.length * 1000) / 10 : 0,
    unknown: observations.length - classified,
    verifiedMachines: productTypes.filter(isMachineProductType).length,
  };
}

type IntelligenceCategoryRow = {
  key: string;
  label: string;
  marketDate?: string;
  observations: Observation[];
  previousObservations?: Observation[];
  history?: Array<{ marketDate: string; observations: Observation[] }>;
  quality?: { complete: boolean };
  comparison: RankingComparison;
};

export type MarketSignalLevel = "high" | "watch" | "activity";
export type MarketSignalKind = "rank_surge" | "rank_drop" | "top10_entry" | "top10_exit" | "first_seen" | "new_entry" | "re_entry" | "exit" | "price_change" | "coupon_added" | "coupon_removed" | "review_momentum" | "review_anomaly" | "brand_expansion" | "brand_contraction";

export type MarketSignal = {
  level: MarketSignalLevel;
  kind: MarketSignalKind;
  asin: string | null;
  brand?: string;
  title: string;
  categoryKey: string;
  categoryLabel: string;
  marketDate: string | null;
  currentRank: number | null;
  previousRank: number | null;
  delta: number | null;
  price: number | null;
  rating: number | null;
  reviews: number | null;
  hasDiscount: boolean | null;
  evidence: "High" | "Verified";
  currentValue?: string | number | null;
  previousValue?: string | number | null;
  magnitude?: number | null;
};

export type MarketState = {
  ready: boolean;
  top10Stability: number | null;
  volatility: "LOW" | "MEDIUM" | "HIGH" | null;
  turnover: "LOW" | "MEDIUM" | "HIGH" | null;
};

export type BrandMovementRow = {
  brand: string;
  previousSeats: number;
  currentSeats: number;
  delta: number;
  verified: boolean;
};

export type ProductIntelligenceRow = Observation & {
  brand: string | null;
  productType: ProductType;
  delta: number | null;
  previousRank: number | null;
  isNew: boolean;
  sevenDayDelta: number | null;
  presenceDays: number;
  presenceWindowDays: number;
  presencePercent: number | null;
};

export const HIGH_PRESENCE_THRESHOLD = 80;

export function marketContextForCategory(categoryKey: string) {
  const category = productionCategoryRegistry.categories.find((candidate) => candidate.enabled && candidate.categoryKey === categoryKey)
    ?? productionCategoryRegistry.categories.find(({ enabled }) => enabled)!;
  const defaultSegment = category.defaults.products;
  return {
    category: category.labelZh,
    segment: category.segments.find(({ key }) => key === defaultSegment)?.labelZh ?? "",
  };
}

export function activityPriorityPresentation(priority: string) {
  if (priority === "high") return { label: "高优先级", tone: "high" } as const;
  if (priority === "watch") return { label: "观察", tone: "medium" } as const;
  return { label: "动态", tone: "low" } as const;
}

export function formatCompactNumber(value: number | null) {
  if (typeof value !== "number" || !Number.isFinite(value)) return "—";
  return new Intl.NumberFormat("en-US", {
    notation: value >= 1000 ? "compact" : "standard",
    maximumFractionDigits: 1,
  }).format(value);
}

export function formatPrice(value: number | null) {
  return typeof value !== "number" || !Number.isFinite(value) ? "—" : `$${value.toFixed(2)}`;
}

export function formatDeal(observation: Pick<Observation, "has_discount" | "discounts"> & { price?: number | null }) {
  if (observation.has_discount === false) return "—";
  if (observation.has_discount !== true) return "优惠信息待确认";
  const amount = observation.discounts.map(({ amount }) => amount.trim()).find(Boolean);
  if (!amount) return "优惠信息待确认";
  return amount
    .replace(/\$(\d+)\.00\b/, "$$$1")
    .replace(/\boff\b/gi, "OFF");
}

export function formatExactNumber(value: number | null) {
  return typeof value !== "number" || !Number.isFinite(value) ? "—" : new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 }).format(value);
}

export function formatReviewChange(previous: number, current: number) {
  const delta = current - previous;
  return `${formatExactNumber(previous)} → ${formatExactNumber(current)}  ${delta >= 0 ? "+" : ""}${formatExactNumber(delta)}`;
}

export function formatRating(value: number | null) {
  return typeof value !== "number" || !Number.isFinite(value) ? "—" : `${value.toFixed(1)} ★`;
}

export function formatPercentage(value: number | null, fractionDigits = 0) {
  return typeof value !== "number" || !Number.isFinite(value) ? "—" : `${value.toFixed(fractionDigits)}%`;
}

export function formatMarketDate(value: string) {
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.valueOf())) return value;
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  }).format(parsed);
}

export function formatCompactDate(value: string) {
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.valueOf())) return value;
  return new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", timeZone: "UTC" }).format(parsed);
}

export function compactProductTitle(value: string, maxLength = 58) {
  const title = value.trim().replace(/\s+/g, " ");
  if (title.length <= maxLength) return title;
  const slice = title.slice(0, Math.max(1, maxLength - 1));
  const lastSpace = slice.lastIndexOf(" ");
  return `${(lastSpace >= Math.floor(maxLength / 2) ? slice.slice(0, lastSpace) : slice).trimEnd()}…`;
}

export function productDisplayName(value: string, brand: string | null = null, maxLength = 58) {
  const normalized = value.trim().replace(/\s+/g, " ");
  const core = normalized.split(/[,;|]|\s+(?:with|includes?|featuring)\s+/i, 1)[0]?.trim() || normalized;
  const prefixed = brand && !core.toLocaleLowerCase("en-US").startsWith(brand.toLocaleLowerCase("en-US"))
    ? `${brand} ${core}`
    : core;
  return compactProductTitle(prefixed, maxLength);
}

export type CanonicalEventState = "first_seen" | "new_entry" | "re_entry" | "exit" | "stable";

export function resolveCanonicalEventState({ hasPreviousValidDay, previousInside, currentInside, historicallyInside }: {
  hasPreviousValidDay: boolean;
  previousInside: boolean;
  currentInside: boolean;
  historicallyInside: boolean;
}): CanonicalEventState {
  if (!hasPreviousValidDay) return currentInside ? "first_seen" : "stable";
  if (previousInside && !currentInside) return "exit";
  if (!previousInside && currentInside) return historicallyInside ? "re_entry" : "new_entry";
  return "stable";
}

export const REVIEW_ANOMALY_MIN_DROP = 100;
export const REVIEW_ANOMALY_MIN_DROP_RATIO = 0.1;

export function isReviewAnomaly(previous: number, current: number) {
  const drop = previous - current;
  return previous > 0 && drop >= REVIEW_ANOMALY_MIN_DROP && drop / previous >= REVIEW_ANOMALY_MIN_DROP_RATIO;
}

export type ProductTimelineEventKind = "first_seen" | "new_entry" | "re_entry" | "exit" | "top10_entry" | "top10_exit" | "price" | "coupon" | "review" | "review_anomaly";

export type ProductTimelineEvent = {
  kind: ProductTimelineEventKind;
  state?: CanonicalEventState;
  marketDate: string;
  detail: string;
};

export function buildProductRankTimeline(history: Array<{ marketDate: string; observations: Observation[] }>, asin: string) {
  const ordered = history.toSorted((left, right) => left.marketDate.localeCompare(right.marketDate));
  const timestamps = ordered.map(({ marketDate }) => Date.parse(`${marketDate}T00:00:00Z`));
  const firstTimestamp = timestamps[0] ?? 0;
  const lastTimestamp = timestamps.at(-1) ?? firstTimestamp;
  const span = Math.max(0, lastTimestamp - firstTimestamp);
  let historicallyInside = false;
  let previousObservation: Observation | null = null;
  const events: ProductTimelineEvent[] = [];
  const points = ordered.map((day, index) => {
    const observation = day.observations.find((row) => row.asin === asin) ?? null;
    const state = resolveCanonicalEventState({
      hasPreviousValidDay: index > 0,
      previousInside: previousObservation !== null,
      currentInside: observation !== null,
      historicallyInside,
    });
    if (state !== "stable") {
      const rank = observation?.rank ?? previousObservation?.rank ?? null;
      const label = state === "first_seen" ? "首次可靠观测" : state === "new_entry" ? "新入榜" : state === "re_entry" ? "重新入榜" : "退出 Top30";
      const detail = state === "exit" && rank !== null
        ? `上一有效市场日 #${rank} → 退出 Top30`
        : rank === null ? label : `${label} #${rank}`;
      events.push({ kind: state, state, marketDate: day.marketDate, detail });
    }
    if (observation && previousObservation) {
      if (previousObservation.rank > 10 && observation.rank <= 10) events.push({ kind: "top10_entry", marketDate: day.marketDate, detail: `#${previousObservation.rank} → #${observation.rank}` });
      if (previousObservation.rank <= 10 && observation.rank > 10) events.push({ kind: "top10_exit", marketDate: day.marketDate, detail: `#${previousObservation.rank} → #${observation.rank}` });
      if (previousObservation.price !== null && observation.price !== null && previousObservation.price !== observation.price) events.push({ kind: "price", marketDate: day.marketDate, detail: `${formatPrice(previousObservation.price)} → ${formatPrice(observation.price)}` });
      if (previousObservation.has_discount !== observation.has_discount) events.push({ kind: "coupon", marketDate: day.marketDate, detail: `${formatDeal(previousObservation)} → ${formatDeal(observation)}` });
      if (previousObservation.reviews !== null && observation.reviews !== null && previousObservation.reviews !== observation.reviews) {
        events.push({ kind: isReviewAnomaly(previousObservation.reviews, observation.reviews) ? "review_anomaly" : "review", marketDate: day.marketDate, detail: formatReviewChange(previousObservation.reviews, observation.reviews) });
      }
    }
    const point = {
      marketDate: day.marketDate,
      observation,
      rank: observation?.rank ?? null,
      delta: observation && previousObservation ? previousObservation.rank - observation.rank : null,
      xPercent: ordered.length <= 1 ? 50 : span > 0 && Number.isFinite(timestamps[index])
        ? Math.round((timestamps[index] - firstTimestamp) / span * 1000) / 10
        : Math.round(index / (ordered.length - 1) * 1000) / 10,
      yPercent: observation ? Math.round((observation.rank - 1) / 29 * 1000) / 10 : null,
    };
    if (observation) historicallyInside = true;
    previousObservation = observation;
    return point;
  });
  const segments: Array<typeof points> = [];
  for (const point of points) {
    if (point.rank === null) continue;
    const previousPoint = points[points.indexOf(point) - 1];
    if (!previousPoint || previousPoint.rank === null) segments.push([]);
    segments.at(-1)!.push(point);
  }
  const labelCount = Math.min(6, points.length);
  const labelIndexes = new Set(Array.from({ length: labelCount }, (_, index) => labelCount === 1 ? 0 : Math.round(index * (points.length - 1) / (labelCount - 1))));
  return {
    points,
    segments,
    events,
    axisLabels: points.filter((_, index) => labelIndexes.has(index)).map(({ marketDate, xPercent }) => ({ marketDate, xPercent })),
  };
}

export function resolveProductTimelineStatus(timeline: ReturnType<typeof buildProductRankTimeline>) {
  const currentPoint = timeline.points.at(-1) ?? null;
  const lastListedPoint = timeline.points.findLast(({ observation }) => observation !== null) ?? null;
  const previousPoint = timeline.points.at(-2) ?? null;
  return {
    currentObservation: currentPoint?.observation ?? null,
    currentMarketDate: currentPoint?.marketDate ?? null,
    lastListedObservation: lastListedPoint?.observation ?? null,
    lastListedMarketDate: lastListedPoint?.marketDate ?? null,
    delta: currentPoint?.observation && previousPoint?.observation
      ? previousPoint.observation.rank - currentPoint.observation.rank
      : null,
  };
}

function signalWeight(level: MarketSignalLevel) {
  return { high: 0, watch: 1, activity: 2 }[level];
}

function movementSignal(row: IntelligenceCategoryRow, mover: RankingMover): MarketSignal {
  const top10Entry = mover.previousRank > 10 && mover.rank <= 10;
  const top10Exit = mover.previousRank <= 10 && mover.rank > 10;
  const level: MarketSignalLevel = top10Entry || top10Exit || mover.absoluteMove >= 20 ? "high" : mover.absoluteMove >= 10 ? "watch" : "activity";
  return {
    level,
    kind: top10Entry ? "top10_entry" : top10Exit ? "top10_exit" : mover.change > 0 ? "rank_surge" : "rank_drop",
    asin: mover.asin,
    title: mover.title,
    categoryKey: row.key,
    categoryLabel: row.label,
    marketDate: row.marketDate ?? null,
    currentRank: mover.rank,
    previousRank: mover.previousRank,
    delta: mover.change,
    price: mover.price,
    rating: mover.rating,
    reviews: mover.reviews,
    hasDiscount: mover.has_discount,
    evidence: level === "high" ? "High" : "Verified",
  };
}

function canonicalBoundarySignal(row: IntelligenceCategoryRow, state: Exclude<CanonicalEventState, "stable">, current: Observation | null, previous: Observation | null): MarketSignal {
  const observation = current ?? previous!;
  const boundaryRank = current?.rank ?? previous?.rank ?? 31;
  const level: MarketSignalLevel = state === "re_entry"
    ? boundaryRank <= 10 ? "high" : "watch"
    : state === "new_entry" || state === "exit"
      ? boundaryRank <= 10 ? "high" : "activity"
      : "activity";
  return {
    level,
    kind: state,
    asin: observation.asin,
    title: observation.title,
    categoryKey: row.key,
    categoryLabel: row.label,
    marketDate: row.marketDate ?? null,
    currentRank: current?.rank ?? null,
    previousRank: previous?.rank ?? null,
    delta: null,
    price: observation.price,
    rating: observation.rating,
    reviews: observation.reviews,
    hasDiscount: observation.has_discount,
    evidence: level === "high" ? "High" : "Verified",
  };
}

function comparableValueSignal(row: IntelligenceCategoryRow, current: Observation, previous: Observation, kind: MarketSignalKind, level: MarketSignalLevel, currentValue: string | number, previousValue: string | number, magnitude: number): MarketSignal {
  return {
    level, kind, asin: current.asin, title: current.title, categoryKey: row.key, categoryLabel: row.label,
    marketDate: row.marketDate ?? null, currentRank: current.rank, previousRank: previous.rank, delta: null,
    price: current.price, rating: current.rating, reviews: current.reviews, hasDiscount: current.has_discount,
    evidence: level === "high" ? "High" : "Verified", currentValue, previousValue, magnitude,
  };
}

export function buildMarketSignals(dashboard: { categoryRows: IntelligenceCategoryRow[]; productMetadata?: ProductMetadata[] }, limit = Number.POSITIVE_INFINITY) {
  const signals: MarketSignal[] = [];
  for (const row of dashboard.categoryRows) {
    const currentAsins = new Set(row.observations.map(({ asin }) => asin));
    const previousRows = row.previousObservations ?? [];
    const previousAsins = new Set(previousRows.map(({ asin }) => asin));
    const previousByAsin = new Map(previousRows.map((observation) => [observation.asin, observation]));
    const currentByAsin = new Map(row.observations.map((observation) => [observation.asin, observation]));
    const baselineDate = row.comparison.baselineDate ?? null;
    const hasPreviousValidDay = row.comparison.ready && baselineDate !== null;
    const history = row.history?.toSorted((left, right) => left.marketDate.localeCompare(right.marketDate)) ?? [];
    if (row.quality?.complete !== false) {
      if (hasPreviousValidDay) {
        const olderAsins = new Set(history
          .filter(({ marketDate }) => marketDate < baselineDate)
          .flatMap(({ observations }) => observations.map(({ asin }) => asin)));
        for (const asin of new Set([...currentAsins, ...previousAsins])) {
          const current = currentByAsin.get(asin) ?? null;
          const previous = previousByAsin.get(asin) ?? null;
          const state = resolveCanonicalEventState({
            hasPreviousValidDay: true,
            previousInside: previous !== null,
            currentInside: current !== null,
            historicallyInside: olderAsins.has(asin),
          });
          if (state !== "stable") signals.push(canonicalBoundarySignal(row, state, current, previous));
        }
      } else if (history.length === 1 && history[0]?.marketDate === row.marketDate) {
        signals.push(...row.observations.map((observation) => canonicalBoundarySignal(row, "first_seen", observation, null)));
      }
    }
    if (!row.comparison.ready) continue;
    signals.push(...(row.comparison.movers ?? []).filter(({ absoluteMove }) => absoluteMove > 0).map((mover) => movementSignal(row, mover)));
    for (const current of row.observations) {
      const previous = previousByAsin.get(current.asin);
      if (!previous) continue;
      if (current.price !== null && previous.price !== null && previous.price > 0 && current.price !== previous.price) {
        const magnitude = Math.abs(current.price - previous.price) / previous.price * 100;
        signals.push(comparableValueSignal(row, current, previous, "price_change", magnitude >= 5 ? "watch" : "activity", current.price, previous.price, Math.round(magnitude * 10) / 10));
      }
      if (current.has_discount !== null && previous.has_discount !== null && current.has_discount !== previous.has_discount) {
        signals.push(comparableValueSignal(row, current, previous, current.has_discount ? "coupon_added" : "coupon_removed", "watch", current.has_discount ? "有优惠" : "无优惠", previous.has_discount ? "有优惠" : "无优惠", 1));
      }
      if (current.reviews !== null && previous.reviews !== null) {
        if (isReviewAnomaly(previous.reviews, current.reviews)) {
          signals.push(comparableValueSignal(row, current, previous, "review_anomaly", "watch", current.reviews, previous.reviews, previous.reviews - current.reviews));
        } else if (current.reviews > previous.reviews) {
          const reviewGrowth = current.reviews - previous.reviews;
          signals.push(comparableValueSignal(row, current, previous, "review_momentum", reviewGrowth >= 10 ? "watch" : "activity", current.reviews, previous.reviews, reviewGrowth));
        }
      }
    }
    if (row.previousObservations && dashboard.productMetadata?.length) {
      for (const movement of buildBrandMovement({ current: row.observations, previous: previousRows, metadata: dashboard.productMetadata })) {
        if (!movement.verified || movement.delta === 0) continue;
        const level: MarketSignalLevel = Math.abs(movement.delta) >= 2 ? "high" : "activity";
        signals.push({
          level,
          kind: movement.delta > 0 ? "brand_expansion" : "brand_contraction",
          asin: null,
          brand: movement.brand,
          title: movement.brand,
          categoryKey: row.key,
          categoryLabel: row.label,
          marketDate: row.marketDate ?? null,
          currentRank: null,
          previousRank: null,
          delta: movement.delta,
          price: null,
          rating: null,
          reviews: null,
          hasDiscount: null,
          evidence: level === "high" ? "High" : "Verified",
          currentValue: movement.currentSeats,
          previousValue: movement.previousSeats,
          magnitude: Math.abs(movement.delta),
        });
      }
    }
  }
  const deduped = new Map<string, MarketSignal>();
  const metadataByAsin = new Map((dashboard.productMetadata ?? []).map((row) => [row.asin, row]));
  for (const signal of signals) {
    const key = `${signal.categoryKey}:${signal.marketDate ?? "unknown"}:${signal.asin ?? signal.brand ?? "market"}:${signal.kind}`;
    const existing = deduped.get(key);
    const metadata = signal.asin ? metadataByAsin.get(signal.asin) : undefined;
    const normalized = signal.asin
      ? { ...signal, title: productDisplayName(signal.title, metadata?.normalizedBrand ?? metadata?.rawBrand ?? null) }
      : signal;
    if (!existing || signalWeight(signal.level) < signalWeight(existing.level)) deduped.set(key, normalized);
  }
  return [...deduped.values()]
    .toSorted((left, right) => signalWeight(left.level) - signalWeight(right.level)
      || Math.abs(right.delta ?? 0) - Math.abs(left.delta ?? 0)
      || (left.currentRank ?? 31) - (right.currentRank ?? 31)
      || (left.asin ?? left.brand ?? "").localeCompare(right.asin ?? right.brand ?? ""))
    .slice(0, Math.max(0, limit));
}

export function groupMarketSignals<T extends { level: MarketSignalLevel }>(signals: T[]) {
  return {
    alerts: signals.filter(({ level }) => level === "high" || level === "watch")
      .toSorted((left, right) => signalWeight(left.level) - signalWeight(right.level)),
    activity: signals.filter(({ level }) => level !== "high" && level !== "watch")
      .toSorted((left, right) => signalWeight(left.level) - signalWeight(right.level)),
  };
}

export function buildMarketState(row: { comparison: RankingComparison }): MarketState {
  const comparison = row.comparison;
  if (!comparison.ready || comparison.top10Retained === null || comparison.top10Retained === undefined
    || comparison.averageAbsoluteMove === null || comparison.averageAbsoluteMove === undefined
    || comparison.entries === null || comparison.entries === undefined
    || comparison.exits === null || comparison.exits === undefined) {
    return { ready: false, top10Stability: null, volatility: null, turnover: null };
  }
  const turnoverCount = comparison.entries + comparison.exits;
  return {
    ready: true,
    top10Stability: comparison.top10Total === 0 ? null : Math.round(comparison.top10Retained / (comparison.top10Total ?? 10) * 100),
    volatility: comparison.averageAbsoluteMove <= 2 ? "LOW" : comparison.averageAbsoluteMove <= 5 ? "MEDIUM" : "HIGH",
    turnover: turnoverCount <= 2 ? "LOW" : turnoverCount <= 6 ? "MEDIUM" : "HIGH",
  };
}

function brandFor(metadata: ProductMetadata | undefined) {
  return metadata?.brandSource !== "unknown" && metadata?.normalizedBrand ? metadata.normalizedBrand : "Unknown";
}

export function buildBrandMovement({ current, previous, metadata }: {
  current: Observation[];
  previous: Observation[];
  metadata: ProductMetadata[];
}) {
  const metadataByAsin = new Map(metadata.map((row) => [row.asin, row]));
  const count = (observations: Observation[]) => {
    const seats = new Map<string, number>();
    for (const row of observations) {
      const brand = brandFor(metadataByAsin.get(row.asin));
      seats.set(brand, (seats.get(brand) ?? 0) + 1);
    }
    return seats;
  };
  const currentSeats = count(current);
  const previousSeats = count(previous);
  return [...new Set([...currentSeats.keys(), ...previousSeats.keys()])]
    .map((brand): BrandMovementRow => ({
      brand,
      previousSeats: previousSeats.get(brand) ?? 0,
      currentSeats: currentSeats.get(brand) ?? 0,
      delta: (currentSeats.get(brand) ?? 0) - (previousSeats.get(brand) ?? 0),
      verified: brand !== "Unknown",
    }))
    .toSorted((left, right) => Number(right.verified) - Number(left.verified)
      || Math.abs(right.delta) - Math.abs(left.delta)
      || right.currentSeats - left.currentSeats
      || left.brand.localeCompare(right.brand));
}

export function buildBrandStructure(observations: Observation[], metadata: ProductMetadata[], limit = 5) {
  const movements = buildBrandMovement({ current: observations, previous: [], metadata });
  const verified = movements.filter(({ verified, currentSeats }) => verified && currentSeats > 0)
    .toSorted((left, right) => right.currentSeats - left.currentSeats || left.brand.localeCompare(right.brand));
  const denominator = observations.length;
  const primary = verified.slice(0, Math.max(0, limit));
  const primaryBrands = new Set(primary.map(({ brand }) => brand));
  const unknownSeats = movements.find(({ brand }) => brand === "Unknown")?.currentSeats ?? 0;
  const otherSeats = movements.filter(({ brand, verified }) => verified && !primaryBrands.has(brand)).reduce((sum, row) => sum + row.currentSeats, 0);
  const rows = [
    ...primary.map(({ brand, currentSeats }) => ({ brand, seats: currentSeats, seatShare: denominator ? Math.round(currentSeats / denominator * 1000) / 10 : 0 })),
    ...(otherSeats ? [{ brand: "其他", seats: otherSeats, seatShare: denominator ? Math.round(otherSeats / denominator * 1000) / 10 : 0 }] : []),
    ...(unknownSeats ? [{ brand: "Unknown", seats: unknownSeats, seatShare: denominator ? Math.round(unknownSeats / denominator * 1000) / 10 : 0 }] : []),
  ];
  const top3Seats = verified.slice(0, 3).reduce((sum, row) => sum + row.currentSeats, 0);
  return {
    rows,
    denominator,
    top3Concentration: denominator ? Math.round(top3Seats / denominator * 1000) / 10 : null,
  };
}

export function buildProductRows({ observations, comparison, metadata, history = [] }: {
  observations: Observation[];
  comparison: RankingComparison;
  metadata: ProductMetadata[];
  history?: Array<{ marketDate: string; observations: Observation[] }>;
}) {
  const metadataByAsin = new Map(metadata.map((row) => [row.asin, row]));
  const moverByAsin = new Map((comparison.movers ?? []).map((row) => [row.asin, row]));
  const trendHistory = history.slice(-8);
  const presenceHistory = history.slice(-30);
  const sevenDayBaseline = trendHistory.length >= 8 ? trendHistory[0] : null;
  return observations.map((observation): ProductIntelligenceRow => {
    const productMetadata = metadataByAsin.get(observation.asin);
    const mover = moverByAsin.get(observation.asin);
    return {
      ...observation,
      brand: productMetadata?.brandSource !== "unknown" ? productMetadata?.normalizedBrand ?? null : null,
      productType: productMetadata?.productType ?? "unknown",
      delta: comparison.ready && mover ? mover.change : null,
      previousRank: comparison.ready && mover ? mover.previousRank : null,
      isNew: comparison.ready && !mover,
      sevenDayDelta: sevenDayBaseline
        ? (sevenDayBaseline.observations.find(({ asin }) => asin === observation.asin)?.rank ?? null) === null
          ? null
          : sevenDayBaseline.observations.find(({ asin }) => asin === observation.asin)!.rank - observation.rank
        : null,
      presenceDays: presenceHistory.filter(({ observations: rows }) => rows.some(({ asin }) => asin === observation.asin)).length,
      presenceWindowDays: presenceHistory.length,
      presencePercent: presenceHistory.length
        ? Math.round(presenceHistory.filter(({ observations: rows }) => rows.some(({ asin }) => asin === observation.asin)).length / presenceHistory.length * 1000) / 10
        : null,
    };
  });
}

export function buildProductTypeStructure(history: TrendDay[], metadata: ProductMetadata[], windowDays = 7) {
  const current = history.at(-1)?.observations ?? [];
  const baseline = history.length >= windowDays + 1 ? history.at(-(windowDays + 1))!.observations : null;
  const productTypeByAsin = new Map(metadata.map(({ asin, productType }) => [asin, productType]));
  const countTypes = (observations: Observation[]) => {
    const counts = new Map<ProductType, number>();
    for (const { asin } of observations) {
      const productType = productTypeByAsin.get(asin) ?? "unknown";
      counts.set(productType, (counts.get(productType) ?? 0) + 1);
    }
    return counts;
  };
  const currentCounts = countTypes(current);
  const baselineCounts = baseline ? countTypes(baseline) : null;
  const productTypes = new Set<ProductType>([
    ...currentCounts.keys(),
    ...(baselineCounts?.keys() ?? []),
  ]);
  return {
    trendReady: baselineCounts !== null,
    windowDays,
    rows: [...productTypes]
      .map((productType) => ({
        productType,
        currentSeats: currentCounts.get(productType) ?? 0,
        seatChange: baselineCounts === null
          ? null
          : (currentCounts.get(productType) ?? 0) - (baselineCounts.get(productType) ?? 0),
      }))
      .filter(({ currentSeats }) => currentSeats > 0)
      .toSorted((left, right) => right.currentSeats - left.currentSeats || left.productType.localeCompare(right.productType)),
  };
}

export const WORTH_STUDY_MAX_REVIEWS = 100;
export const WORTH_STUDY_MIN_RANK_GAIN = 10;

export function buildWorthStudyingProducts(rows: ProductIntelligenceRow[]) {
  return rows
    .flatMap((row) => {
      if (row.reviews === null || row.reviews > WORTH_STUDY_MAX_REVIEWS || row.delta === null || row.delta < WORTH_STUDY_MIN_RANK_GAIN) return [];
      const enteredTop10 = row.rank <= 10 && row.previousRank !== null && row.previousRank > 10;
      return [{ ...row, reason: enteredTop10 ? "低评论 · 快速进入 Top10" : "低评论 · 排名快速上升" }];
    })
    .toSorted((left, right) => right.delta - left.delta || left.rank - right.rank)
    .slice(0, 5);
}

export function buildReviewCompetition(observations: Observation[]) {
  const top10 = observations.filter(({ rank, reviews }) => rank <= 10 && reviews !== null).map(({ reviews }) => reviews!);
  const top30 = observations.filter(({ reviews }) => reviews !== null).map(({ reviews }) => reviews!);
  return {
    top10Median: median(top10),
    top30Median: median(top30),
    top10Minimum: top10.length ? Math.min(...top10) : null,
    top10SampleSize: top10.length,
    top30SampleSize: top30.length,
  };
}

export function validateDealDisplay(input: {
  currentPrice: number | null;
  referencePrice: number | null;
  discount: number | null;
  hasDiscount: boolean | null;
  label?: string | null;
}) {
  if (input.hasDiscount === false) return { valid: true, label: "—" } as const;
  const valid = input.hasDiscount === true
    && input.currentPrice !== null && input.currentPrice > 0
    && input.referencePrice !== null && input.referencePrice >= input.currentPrice
    && input.discount !== null && input.discount >= 0;
  return valid
    ? { valid: true, label: input.label?.trim() || "有优惠" } as const
    : { valid: false, label: "优惠信息待确认" } as const;
}

type TrendDay = { marketDate: string; observations: Observation[] };

export function median(values: number[]) {
  if (!values.length) return null;
  const sorted = values.toSorted((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : Math.round((sorted[middle - 1] + sorted[middle]) * 50) / 100;
}

function direction(current: number | null, previous: number | null) {
  if (current === null || previous === null || current === previous) return "neutral" as const;
  return current > previous ? "up" as const : "down" as const;
}

function windowMetrics(days: TrendDay[], metadata: ProductMetadata[] = []) {
  const current = days.at(-1)?.observations ?? [];
  const first = days[0]?.observations ?? [];
  const currentTop10 = new Set(current.filter(({ rank }) => rank <= 10).map(({ asin }) => asin));
  const firstTop10 = new Set(first.filter(({ rank }) => rank <= 10).map(({ asin }) => asin));
  const retained = [...currentTop10].filter((asin) => firstTop10.has(asin)).length;
  const entries = current.filter(({ asin }) => !new Set(first.map((row) => row.asin)).has(asin)).length;
  const exits = first.filter(({ asin }) => !new Set(current.map((row) => row.asin)).has(asin)).length;
  const top3Concentration = metadata.length ? buildBrandStructure(current, metadata).top3Concentration : null;
  return {
    top10Stability: firstTop10.size ? Math.round(retained / firstTop10.size * 1000) / 10 : null,
    turnover: entries + exits,
    medianPrice: median(current.flatMap(({ price }) => price === null ? [] : [price])),
    top3Concentration,
  };
}

export function buildMarketTrend(history: TrendDay[], windowDays: number, metadata: ProductMetadata[] = []) {
  if (windowDays <= 0 || history.length < windowDays * 2) return { ready: false as const, windowDays };
  const currentDays = history.slice(-windowDays);
  const previousDays = history.slice(-windowDays * 2, -windowDays);
  const current = windowMetrics(currentDays, metadata);
  const previous = windowMetrics(previousDays, metadata);
  return {
    ready: true as const,
    windowDays,
    current: { validDays: currentDays.length, startDate: currentDays[0].marketDate, endDate: currentDays.at(-1)!.marketDate },
    previous: { validDays: previousDays.length, startDate: previousDays[0].marketDate, endDate: previousDays.at(-1)!.marketDate },
    metrics: {
      top10Stability: { current: current.top10Stability, previous: previous.top10Stability, direction: direction(current.top10Stability, previous.top10Stability) },
      turnover: { current: current.turnover, previous: previous.turnover, direction: direction(current.turnover, previous.turnover) },
      top3Concentration: { current: current.top3Concentration, previous: previous.top3Concentration, direction: direction(current.top3Concentration, previous.top3Concentration) },
      medianPrice: { current: current.medianPrice, previous: previous.medianPrice, direction: direction(current.medianPrice, previous.medianPrice) },
    },
  };
}

export function buildBrandSeatTrend(history: TrendDay[], metadata: ProductMetadata[], windowDays = 7) {
  if (history.length < windowDays + 1) return [];
  const current = history.at(-1)!.observations;
  const previous = history.at(-(windowDays + 1))!.observations;
  return buildBrandMovement({ current, previous, metadata }).filter(({ verified }) => verified);
}
