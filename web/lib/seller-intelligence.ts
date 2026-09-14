import { type Observation } from "./analytics.ts";
import { categories, categoryByKey, type CategoryKey } from "./catalog.ts";
import { createD1DashboardStore } from "./dashboard-store.ts";
import { getD1 } from "./d1.ts";
import { loadVerifiedDashboardFromStore, type DashboardView } from "./live-dashboard-data.ts";
import { isValidMarketDate } from "./public-validation.ts";
import { readExplicitSpecificationsForCategory, readExplicitSpecificationsForProduct } from "./product-specs.ts";
import { validateMarketContext, type MarketContext } from "./market-context.ts";
import { buildAnalyticalCategory, buildMarketSignals, type MarketSignal } from "./ui-intelligence.ts";
import {
  validateSellerIntelligenceReport,
  type SellerIntelligenceReport,
  type SellerProfile,
  type SellerSignal,
  type SellerStrategyFacts,
} from "./seller-intelligence-contract.ts";

const liveCacheHeader = { "cache-control": "public, max-age=300" };
const fallbackCacheHeader = { "cache-control": "public, max-age=60" };
const overviewScope = "overview";
const generatorVersionPattern = /^seller-rules-v\d+(?:\.\d+)*$/;
const sha256Pattern = /^[a-f0-9]{64}$/i;

function average(values: number[]) {
  return values.length ? Math.round((values.reduce((sum, value) => sum + value, 0) / values.length) * 10) / 10 : 0;
}

function countVerifiableDiscounts(observations: Observation[]) {
  const verifiable = observations.filter(({ has_discount }) => has_discount !== null).length;
  return observations.length ? Math.round((verifiable / observations.length) * 1000) / 10 : 0;
}

function sha256(value: unknown) {
  return crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(value))).then((hash) =>
    Array.from(new Uint8Array(hash), (byte) => byte.toString(16).padStart(2, "0")).join(""),
  );
}

function isProfile(value: string | null): value is SellerProfile {
  return value === "seller_alert" || value === "competition_strategy";
}

function isCategory(value: string | null): value is CategoryKey {
  return Boolean(value && categories.some((category) => category.key === value));
}

function safeListKey(value: string) {
  const match = value.match(/^(seller-alert\/daily|competition-strategy\/weekly)\/\d{4}-\d{2}-\d{2}\/([a-z0-9_]+)\.json$/);
  return Boolean(match && (match[2] === overviewScope || isCategory(match[2])));
}

function liveKey(profile: SellerProfile, marketDate: string, categoryKey: CategoryKey | null) {
  const scope = categoryKey ?? overviewScope;
  return profile === "seller_alert"
    ? `seller-alert/daily/${marketDate}/${scope}.json`
    : `competition-strategy/weekly/${marketDate}/${scope}.json`;
}

function labelFor(categoryKey: CategoryKey | null, rows: DashboardView["categoryRows"]) {
  if (categoryKey) return categoryByKey[categoryKey]?.label ?? "所选榜单";
  return rows.length === categories.length ? "全部榜单" : "当前范围";
}

function qualityDisclosure(label: string, rows: DashboardView["categoryRows"]) {
  const missing = rows
    .filter((row) => !row.quality.complete)
    .map((row) => `${row.label} 当前仅采集到 ${row.observations.length} 条记录`)
    .join("；");
  return missing || `${label} 当前数据不完整，暂不下结论。`;
}

function canonicalKind(signal: MarketSignal): SellerSignal["kind"] {
  if (signal.kind === "rank_surge" || signal.kind === "rank_drop") return "rank_move";
  if (signal.kind === "coupon_added" || signal.kind === "coupon_removed") return "discount_change";
  return signal.kind;
}

function rawDiscountState(observation: Observation | undefined) {
  if (!observation || observation.has_discount === null) return null;
  if (!observation.has_discount) return "none";
  const values = observation.discounts.map(({ kind, amount }) => `${kind}:${amount}`).toSorted();
  return values.length ? values.join("; ") : null;
}

function buildAlertSignals(rows: DashboardView["categoryRows"], productMetadata: DashboardView["productMetadata"]): SellerSignal[] {
  const rowByKey = new Map<string, DashboardView["categoryRows"][number]>(rows.map((row) => [row.key, row]));
  return buildMarketSignals({ categoryRows: rows, productMetadata }).map((signal) => {
    const kind = canonicalKind(signal);
    const sourceRow = rowByKey.get(signal.categoryKey);
    const discountBefore = signal.kind === "coupon_added" || signal.kind === "coupon_removed" ? rawDiscountState(sourceRow?.previousObservations?.find(({ asin }) => asin === signal.asin)) : undefined;
    const discountAfter = signal.kind === "coupon_added" || signal.kind === "coupon_removed" ? rawDiscountState(sourceRow?.observations.find(({ asin }) => asin === signal.asin)) : undefined;
    return {
      priority: signal.level,
      kind,
      asin: signal.asin,
      ...(signal.brand ? { brand: signal.brand } : {}),
      currentRank: signal.currentRank,
      previousRank: signal.previousRank,
      checks: kind === "review_momentum" || kind === "review_anomaly" ? ["核查评论数与详情页变化"] : kind === "brand_expansion" || kind === "brand_contraction" ? ["核查品牌归一化与 Top30 席位"] : ["核查价格、优惠与详情页变化"],
      evidence: [signal.brand
        ? `${signal.categoryLabel} · ${signal.brand} · ${signal.previousValue} 席 → ${signal.currentValue} 席`
        : `${signal.categoryLabel} · ${signal.kind} · ${signal.previousRank === null ? "榜外" : `#${signal.previousRank}`} → ${signal.currentRank === null ? "榜外" : `#${signal.currentRank}`}`],
      ...(discountBefore && discountAfter ? { discountBefore, discountAfter } : {}),
      ...(signal.currentValue !== undefined ? { currentValue: signal.currentValue, previousValue: signal.previousValue } : {}),
    };
  });
}

function emptyStrategyFacts(): SellerStrategyFacts {
  return { priceBands: null, rankingConcentration: null, topStability: null, competitorPool: null, specificationTrend: null };
}

function priceBands(observations: Observation[]) {
  const values = observations.flatMap(({ price }) => price === null ? [] : [price]).toSorted((left, right) => left - right);
  if ((values.length / observations.length) * 100 < 80) return null;
  const size = Math.max(1, Math.ceil(values.length / 3));
  return Array.from({ length: Math.ceil(values.length / size) }, (_, index) => {
    const sample = values.slice(index * size, (index + 1) * size);
    return { lower: sample[0], upper: sample.at(-1)!, sampleSize: sample.length };
  });
}

function buildCompetitorPool(history: NonNullable<DashboardView["categoryRows"][number]["history"]>): SellerStrategyFacts["competitorPool"] {
  if (history.length < 5) return null;
  const records = new Map<string, { asin: string; title: string; ranks: number[]; daysPresent: number; top10Appearances: number }>();
  for (const snapshot of history) for (const observation of snapshot.observations) {
    const record = records.get(observation.asin) ?? { asin: observation.asin, title: observation.title, ranks: [], daysPresent: 0, top10Appearances: 0 };
    record.ranks.push(observation.rank);
    record.daysPresent += 1;
    if (observation.rank <= 10) record.top10Appearances += 1;
    records.set(observation.asin, record);
  }
  return [...records.values()]
    .map((record) => {
      const maxAbsoluteMovement = record.ranks.slice(1).reduce((largest, rank, index) => Math.max(largest, Math.abs(rank - record.ranks[index])), 0);
      const latestRank = history.at(-1)?.observations.find(({ asin }) => asin === record.asin)?.rank ?? null;
      const priority = record.top10Appearances > 0 || record.daysPresent >= 3 || maxAbsoluteMovement >= 10 ? "medium" as const : "low" as const;
      return { ...record, latestRank, maxAbsoluteMovement, priority };
    })
    .toSorted((left, right) => (left.priority === right.priority ? (left.latestRank ?? 31) - (right.latestRank ?? 31) : left.priority === "medium" ? -1 : 1));
}

function buildStrategyFacts(rows: DashboardView["categoryRows"], completeMarketDays: number, metadata: DashboardView["productMetadata"]): SellerStrategyFacts {
  if (rows.length !== 1 || completeMarketDays < 5 || !rows[0].quality.complete) return emptyStrategyFacts();
  const row = rows[0];
  const prices = priceBands(row.observations);
  const totalRankWeight = row.observations.reduce((sum, observation) => sum + (31 - observation.rank), 0);
  const top10RankWeight = row.observations.filter(({ rank }) => rank <= 10).reduce((sum, observation) => sum + (31 - observation.rank), 0);
  const previousObservations = row.previousObservations
    ?? row.history?.find(({ marketDate }) => marketDate === row.comparison.baselineDate)?.observations
    ?? [];
  const previousTop10 = new Set(previousObservations.filter(({ rank }) => rank <= 10).map(({ asin }) => asin));
  const currentTop10 = new Set(row.observations.filter(({ rank }) => rank <= 10).map(({ asin }) => asin));
  const topStability = row.comparison.ready && row.comparison.baselineDate
    ? {
        retainedTop10: [...currentTop10].filter((asin) => previousTop10.has(asin)).length,
        entries: [...currentTop10].filter((asin) => !previousTop10.has(asin)).length,
        exits: [...previousTop10].filter((asin) => !currentTop10.has(asin)).length,
        baselineDate: row.comparison.baselineDate,
      }
    : null;
  const metadataByAsin = new Map(metadata.map((item) => [item.asin, item]));
  const specs = row.observations.map((observation) => {
    const metadata = metadataByAsin.get(observation.asin);
    return metadata
      ? readExplicitSpecificationsForProduct(row.key, metadata.productType, observation.title)
      : readExplicitSpecificationsForCategory(row.key, observation.title);
  });
  const specificationCoverage = row.observations.length ? Math.round((specs.filter((values) => values.length > 0).length / row.observations.length) * 1000) / 10 : 0;
  return {
    priceBands: prices,
    rankingConcentration: totalRankWeight ? { top10RankWeightPercent: Math.round((top10RankWeight / totalRankWeight) * 1000) / 10, top10Slots: row.observations.filter(({ rank }) => rank <= 10).length } : null,
    topStability,
    competitorPool: buildCompetitorPool(row.history ?? []),
    specificationTrend: specificationCoverage >= 80
      ? { coverage: specificationCoverage, observedFields: [...new Set(specs.flatMap((values) => values.map(({ label }) => label)))].toSorted() }
      : null,
  };
}

function sampleSize(rows: DashboardView["categoryRows"]) {
  return rows.reduce((sum, row) => sum + row.observations.length, 0);
}

function fieldCoverage(rows: DashboardView["categoryRows"], metadata: DashboardView["productMetadata"]) {
  const metadataByAsin = new Map(metadata.map((item) => [item.asin, item]));
  return {
    price: average(rows.map((row) => row.priceCoverage.percent)),
    rating: average(rows.map((row) => row.ratingCoverage.percent)),
    reviews: average(rows.map((row) => row.reviewsCoverage.percent)),
    discount: average(rows.map((row) => countVerifiableDiscounts(row.observations))),
    specs: average(rows.map((row) => {
      const withSpecs = row.observations.filter((observation) => {
        const metadata = metadataByAsin.get(observation.asin);
        return (metadata
          ? readExplicitSpecificationsForProduct(row.key, metadata.productType, observation.title)
          : readExplicitSpecificationsForCategory(row.key, observation.title)).length > 0;
      }).length;
      return row.observations.length ? Math.round((withSpecs / row.observations.length) * 1000) / 10 : 0;
    })),
  };
}

function scopeCompleteMarketDays(data: DashboardView, rows: DashboardView["categoryRows"], categoryKey: CategoryKey | null) {
  return categoryKey && rows.length === 1 ? rows[0].completeMarketDays ?? data.completeMarketDays : data.completeMarketDays;
}

function exactComparisonReady(rows: DashboardView["categoryRows"]) {
  return rows.length > 0 && rows.every((row) => row.quality.complete && row.comparison.ready && row.comparison.baselineDate);
}

export function parseSellerIntelligenceListQuery(url: URL) {
  const profile = url.searchParams.get("profile");
  const category = url.searchParams.get("category");
  const date = url.searchParams.get("date");
  const segment = url.searchParams.get("segment");

  if (profile && !isProfile(profile)) return { ok: false as const, error: "invalid_profile" };
  if (category && !isCategory(category)) return { ok: false as const, error: "invalid_category" };
  if (segment && (!category || !validateMarketContext({ marketplace: "US", category, segment }).ok)) return { ok: false as const, error: "unsupported_market_context" };
  if (date && !isValidMarketDate(date)) return { ok: false as const, error: "invalid_date" };

  return {
    ok: true as const,
    profile: profile as SellerProfile | null,
    category: category as CategoryKey | null,
    date: date ?? null,
  };
}

export function parseSellerIntelligenceLiveQuery(url: URL) {
  const profile = url.searchParams.get("profile") ?? "seller_alert";
  const category = url.searchParams.get("category");
  const segment = url.searchParams.get("segment");
  const date = url.searchParams.get("date");

  if (!isProfile(profile)) return { ok: false as const, error: "invalid_profile" };
  if (category && !isCategory(category)) return { ok: false as const, error: "invalid_category" };
  const validatedContext = category && segment ? validateMarketContext({ marketplace: "US", category, segment }) : null;
  if (segment && (!category || !validatedContext?.ok)) return { ok: false as const, error: "unsupported_market_context" };
  if (date && !isValidMarketDate(date)) return { ok: false as const, error: "invalid_date" };
  if (profile === "seller_alert" && !category) return { ok: false as const, error: "invalid_category" };

  return {
    ok: true as const,
    profile: profile as SellerProfile,
    category: category as CategoryKey | null,
    context: validatedContext?.ok ? validatedContext.context : null,
    date: date ?? null,
  };
}

export function isSafeSellerIntelligenceKey(key: string) {
  return safeListKey(key);
}

type SellerIntelligenceListRow = {
  key: string;
  report_kind: string;
  profile: string;
  market_date: string;
  category_key: string | null;
  generated_at: string;
  generator_version: string;
  content_sha256: string;
};

function readKeyScope(key: string): CategoryKey | typeof overviewScope | null {
  const match = key.match(/\/([a-z0-9_]+)\.json$/);
  return match && (match[1] === overviewScope || isCategory(match[1]))
    ? match[1] as CategoryKey | typeof overviewScope
    : null;
}

function isSafeSellerIntelligenceMetadataRow(row: unknown): row is SellerIntelligenceListRow {
  if (!row || typeof row !== "object") return false;
  const candidate = row as Partial<SellerIntelligenceListRow>;
  if (typeof candidate.key !== "string" || !safeListKey(candidate.key)) return false;
  if (candidate.report_kind !== "daily" && candidate.report_kind !== "weekly") return false;
  if (!isProfile(typeof candidate.profile === "string" ? candidate.profile : null)) return false;
  if (!isValidMarketDate(String(candidate.market_date ?? ""))) return false;
  if (typeof candidate.generated_at !== "string" || Number.isNaN(Date.parse(candidate.generated_at))) return false;
  if (typeof candidate.generator_version !== "string" || !generatorVersionPattern.test(candidate.generator_version)) return false;
  if (typeof candidate.content_sha256 !== "string" || !sha256Pattern.test(candidate.content_sha256)) return false;

  const scope = readKeyScope(candidate.key);
  if (scope === null) return false;
  if (candidate.profile === "seller_alert" && candidate.report_kind !== "daily") return false;
  if (candidate.profile === "competition_strategy" && candidate.report_kind !== "weekly") return false;

  if (scope === overviewScope) {
    return candidate.category_key === null;
  }

  return candidate.category_key === scope;
}

export async function listSellerIntelligenceReports(filters: {
  profile: SellerProfile | null;
  category: CategoryKey | null;
  date: string | null;
}) {
  const clauses: string[] = [];
  const values: string[] = [];
  if (filters.profile) {
    clauses.push("profile = ?");
    values.push(filters.profile);
  }
  if (filters.category) {
    clauses.push("category_key = ?");
    values.push(filters.category);
  }
  if (filters.date) {
    clauses.push("market_date = ?");
    values.push(filters.date);
  }
  const where = clauses.length ? ` WHERE ${clauses.join(" AND ")}` : "";
  const db = getD1();
  const rows = await db
    .prepare(
      `SELECT key, report_kind, profile, market_date, category_key, generated_at, generator_version, content_sha256 FROM seller_intelligence_reports${where} ORDER BY market_date DESC, report_kind, profile, category_key LIMIT 100`,
    )
    .bind(...values)
    .all();
  return rows.results.filter(isSafeSellerIntelligenceMetadataRow);
}

export async function readSellerIntelligenceReport(key: string) {
  const db = getD1();
  const row = await db
    .prepare("SELECT content_json FROM seller_intelligence_reports WHERE key = ?")
    .bind(key)
    .first<{ content_json: string }>();
  if (!row) return { status: "not_found" } as const;

  let parsed: unknown;
  try {
    parsed = JSON.parse(row.content_json);
  } catch {
    return { status: "not_found" } as const;
  }

  const validated = validateSellerIntelligenceReport(parsed);
  if (!validated.ok) return { status: "not_found" } as const;
  return { status: "found", report: validated.report } as const;
}

export async function loadVerifiedLiveDashboardFromD1(marketDate?: string) {
  const db = getD1();
  return loadVerifiedDashboardFromStore(createD1DashboardStore(db), { marketDate });
}

export async function buildLiveSellerIntelligence(
  data: DashboardView,
  options: { profile: SellerProfile; categoryKey: CategoryKey | null; context?: MarketContext },
): Promise<SellerIntelligenceReport> {
  const categoryRows = options.categoryKey
    ? data.categoryRows.filter((row) => row.key === options.categoryKey)
    : data.categoryRows;
  const rows = options.context
    ? categoryRows.map((row) => buildAnalyticalCategory(row, data.productMetadata ?? [], options.context!))
    : categoryRows;
  const complete = rows.length > 0 && rows.every((row) => row.quality.complete);
  const scopeMarketDate = rows[0]?.marketDate ?? data.marketDate;
  const completeMarketDays = scopeCompleteMarketDays(data, rows, options.categoryKey);
  const label = labelFor(options.categoryKey, rows);

  let sections: SellerIntelligenceReport["sections"];
  let signals: SellerSignal[] = [];
  let strategy: SellerStrategyFacts | undefined;

  if (!rows.length) {
    sections = [{ title: "数据质量", statements: ["当前范围暂无已验证的公开数据。"] }];
  } else if (options.profile === "seller_alert") {
    if (!complete) {
      sections = [
        { title: "经营预警", statements: [`${label} 当前数据不完整，暂不下结论。`] },
        { title: "数据质量", statements: [qualityDisclosure(label, rows)] },
      ];
    } else if (!exactComparisonReady(rows)) {
      sections = [
        { title: "经营预警", statements: [`${label} 暂无可比完整市场日，当前仅保留完整 Top 30 的排名事实。`] },
        { title: "数据质量", statements: ["需要相邻两个完整 Top 30 市场日后，才展示待核查的排名变化信号。"] },
      ];
    } else {
      signals = buildAlertSignals(rows, data.productMetadata ?? []);
      const highCount = signals.filter((signal) => signal.priority === "high").length;
      const watchCount = signals.filter((signal) => signal.priority === "watch").length;
      const activityCount = signals.filter((signal) => signal.priority === "activity").length;
      sections = [
        {
          title: "经营预警",
          statements: [
            `${label} 当前与上一完整市场日均为完整 Top 30，本页只输出可核查的排名事实与待核查事项。`,
            highCount || watchCount || activityCount
              ? `本次识别 High ${highCount}、Watch ${watchCount}、Activity ${activityCount}。`
              : "未发现可验证的市场变化信号。",
          ],
        },
        {
          title: "数据质量",
          statements: rows.map((row) => `${row.label} 比较基线为 ${row.comparison.baselineDate}，当前仅展示公开可验证的名次变化，不推断原因。`),
        },
      ];
    }
  } else if (completeMarketDays < 5) {
    strategy = emptyStrategyFacts();
    sections = [
      { title: "数据质量", statements: [`${label} 当前仅有 ${completeMarketDays} 个完整市场日，数据积累中，暂不下结论。`] },
      { title: "证据说明", statements: ["完整市场日不足五天时，只保留质量披露与公开排名事实。"] },
    ];
  } else if (!complete) {
    strategy = emptyStrategyFacts();
    sections = [
      { title: "竞争策略", statements: [`${label} 当前数据不完整，暂不下结论。`] },
      { title: "数据质量", statements: [qualityDisclosure(label, rows)] },
    ];
  } else {
    strategy = buildStrategyFacts(rows, completeMarketDays, data.productMetadata ?? []);
    sections = [
      { title: "竞争策略", statements: [`${label} 已积累 ${completeMarketDays} 个完整市场日；以下仅展示通过各自证据门禁的结构化观察。`] },
      { title: "字段覆盖", statements: [`价格字段覆盖率约 ${fieldCoverage(rows, data.productMetadata ?? []).price}%，规格字段覆盖率约 ${fieldCoverage(rows, data.productMetadata ?? []).specs}%。`] },
    ];
  }

  const draft = {
    schemaVersion: "seller-intelligence-v1" as const,
    key: liveKey(options.profile, scopeMarketDate, options.categoryKey),
    reportKind: options.profile === "seller_alert" ? "daily" as const : "weekly" as const,
    profile: options.profile,
    marketDate: scopeMarketDate,
    categoryKey: options.categoryKey,
    generatedAt: data.observedAt,
    generatorVersion: "seller-rules-v1",
    evidence: {
      complete,
      completeMarketDays,
      sampleSize: sampleSize(rows),
      fieldCoverage: fieldCoverage(rows, data.productMetadata ?? []),
    },
    signals,
    sections,
    limitations: [
      "描述性观察，不代表销量、利润或选品成功预测。",
      "待核查事项仅提示人工复核方向，不自动给出原因归因。",
      "缺失字段保持为空，不以零值代替未采集或未验证的数据。",
    ],
    ...(strategy ? { strategy } : {}),
  };

  const report = { ...draft, contentSha256: await sha256(draft) };
  const validated = validateSellerIntelligenceReport(report);
  if (!validated.ok) {
    throw new Error(validated.errors.join("; "));
  }
  return validated.report;
}

export { fallbackCacheHeader, liveCacheHeader };
