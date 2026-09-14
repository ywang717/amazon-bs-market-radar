export type Discount = {
  kind: "COUPON" | "PRICE_DROP" | "PRIME_EXCLUSIVE";
  amount: string;
};

export type Observation = {
  rank: number;
  asin: string;
  title: string;
  url: string;
  price: number | null;
  rating: number | null;
  reviews: number | null;
  has_discount: boolean | null;
  discounts: Discount[];
};

export function formatDiscount(observation: Pick<Observation, "has_discount" | "discounts">) {
  if (observation.has_discount === null) return "等待核验";
  if (!observation.has_discount) return "无优惠";
  const amounts = observation.discounts.map(({ amount }) => amount).filter(Boolean);
  return amounts.length ? amounts.join("；") : "已核验有优惠";
}

const expectedRanks = Array.from({ length: 30 }, (_, index) => index + 1);

export function validateCategory(observations: Observation[]) {
  const ranks = new Set(observations.map(({ rank }) => rank));
  const asins = new Set(observations.map(({ asin }) => asin));
  const missingRanks = expectedRanks.filter((rank) => !ranks.has(rank));
  const invalidRanks = observations.filter(({ rank }) => !Number.isInteger(rank) || rank < 1 || rank > 30).map(({ rank }) => rank);
  return {
    complete: observations.length === 30 && missingRanks.length === 0 && invalidRanks.length === 0 && asins.size === 30,
    observationCount: observations.length,
    missingRanks,
    invalidRanks,
    duplicateAsins: observations.length - asins.size,
  };
}
export function evidenceLevel(completeMarketDays: number) {
  if (completeMarketDays >= 5) return "充分";
  if (completeMarketDays >= 2) return "可用";
  return "有限";
}

export function fieldCoverage(observations: Observation[], field: "price" | "rating" | "reviews") {
  const present = observations.filter((row) => row[field] !== null && row[field] !== undefined).length;
  const total = observations.length;
  const percent = total === 0 ? 0 : Math.round((present / total) * 1000) / 10;
  return { present, total, percent, ready: percent >= 80 };
}

export function compareRankings(previous: Observation[], current: Observation[]) {
  if (!validateCategory(previous).complete || !validateCategory(current).complete) {
    return {
      ready: false,
      reason: "需要相邻两个完整 Top 30 市场日",
      averageAbsoluteMove: null,
      maxAbsoluteMove: null,
      top10Retained: null,
      entries: null,
      exits: null,
      largeMoves: null,
      highPriorityMoves: null,
      movementBands: null,
      movers: [],
    };
  }

  const previousByAsin = new Map(previous.map((row) => [row.asin, row]));
  const currentByAsin = new Map(current.map((row) => [row.asin, row]));
  const movers = current
    .filter((row) => previousByAsin.has(row.asin))
    .map((row) => {
      const previousRank = previousByAsin.get(row.asin)!.rank;
      return { ...row, previousRank, change: previousRank - row.rank, absoluteMove: Math.abs(previousRank - row.rank) };
    })
    .sort((a, b) => b.absoluteMove - a.absoluteMove || a.rank - b.rank);
  const movements = movers.map(({ absoluteMove }) => absoluteMove);
  const previousTop10 = new Set(previous.filter(({ rank }) => rank <= 10).map(({ asin }) => asin));
  const currentTop10 = current.filter(({ rank }) => rank <= 10).map(({ asin }) => asin);

  if (movers.length === 0) {
    return {
      ready: false,
      reason: "没有共同商品，排名变动暂不可比较",
      averageAbsoluteMove: null,
      maxAbsoluteMove: null,
      top10Retained: 0,
      entries: current.length,
      exits: previous.length,
      largeMoves: null,
      highPriorityMoves: null,
      movementBands: null,
      movers: [],
    };
  }

  return {
    ready: true,
    reason: null,
    averageAbsoluteMove: Math.round((movements.reduce((sum, value) => sum + value, 0) / movements.length) * 10) / 10,
    maxAbsoluteMove: Math.max(...movements),
    top10Retained: currentTop10.filter((asin) => previousTop10.has(asin)).length,
    entries: current.filter(({ asin }) => !previousByAsin.has(asin)).length,
    exits: previous.filter(({ asin }) => !currentByAsin.has(asin)).length,
    largeMoves: movements.filter((value) => value >= 10).length,
    highPriorityMoves: movements.filter((value) => value >= 20).length,
    movementBands: {
      stable: movements.filter((value) => value <= 2).length,
      moderate: movements.filter((value) => value >= 3 && value <= 5).length,
      notable: movements.filter((value) => value >= 6 && value <= 9).length,
      large: movements.filter((value) => value >= 10).length,
    },
    movers,
  };
}
