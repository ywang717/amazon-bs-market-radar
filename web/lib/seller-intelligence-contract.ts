import { categories, type CategoryKey } from "./catalog.ts";

export type SellerProfile = "seller_alert" | "competition_strategy";
export type SellerReportKind = "daily" | "weekly";
export type SellerPriority = "high" | "watch" | "activity";
export type SellerSignalKind =
  | "rank_move"
  | "top10_entry"
  | "top10_exit"
  | "top30_entry"
  | "top30_exit"
  | "reentry"
  | "first_seen"
  | "new_entry"
  | "re_entry"
  | "exit"
  | "price_change"
  | "review_momentum"
  | "review_anomaly"
  | "discount_change"
  | "brand_expansion"
  | "brand_contraction";

export type SellerSignal = {
  priority: SellerPriority;
  kind: SellerSignalKind;
  asin: string | null;
  brand?: string;
  currentRank: number | null;
  previousRank: number | null;
  checks: string[];
  evidence: string[];
  discountBefore?: string | null;
  discountAfter?: string | null;
  currentValue?: string | number | null;
  previousValue?: string | number | null;
};

export type SellerStrategyFacts = {
  priceBands: Array<{ lower: number; upper: number; sampleSize: number }> | null;
  rankingConcentration: { top10RankWeightPercent: number; top10Slots: number } | null;
  topStability: { retainedTop10: number; entries: number; exits: number; baselineDate: string } | null;
  competitorPool: Array<{
    asin: string;
    title: string;
    daysPresent: number;
    top10Appearances: number;
    latestRank: number | null;
    maxAbsoluteMovement: number;
    priority: "medium" | "low";
  }> | null;
  specificationTrend: { coverage: number; observedFields: string[] } | null;
};

export type SellerIntelligenceReport = {
  schemaVersion: "seller-intelligence-v1";
  key: string;
  reportKind: SellerReportKind;
  profile: SellerProfile;
  marketDate: string;
  categoryKey: CategoryKey | null;
  generatedAt: string;
  generatorVersion: string;
  contentSha256: string;
  evidence: {
    complete: boolean;
    completeMarketDays: number;
    sampleSize: number;
    fieldCoverage: {
      price: number;
      rating: number;
      reviews: number;
      discount: number;
      specs: number;
    };
  };
  signals: SellerSignal[];
  sections: Array<{ title: string; statements: string[] }>;
  limitations: string[];
  strategy?: SellerStrategyFacts;
};

export type SellerIntelligenceBundle = {
  reports: SellerIntelligenceReport[];
};

const sha256 = /^[a-f0-9]{64}$/i;
const asinPattern = /^[A-Z0-9]{10}$/;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;
const privateDetail =
  /(?:[A-Z]:\\|\/Users\/|smtp|password|secret|authorization|api[_-]?key|bearer\s+[a-z0-9._-]+|@|\btask[-_\s]?\d+\b|\bdatabase\b|\bbackup\b|\binternal error\b|\bstack trace\b|\bexception\b|\bsqlstate\b)/i;
const weeklyTrendTerms = /趋势|周度|策略|关联|相关|因果|份额/;
const sellerBundleScopes: readonly (CategoryKey | "overview")[] = ["overview", ...categories.map(({ key }) => key)];
const categoryKeys = new Set<string>(categories.map(({ key }) => key));

function isIntegerOrNull(value: unknown): value is number | null {
  return value === null || (Number.isInteger(value) && Number(value) >= 0);
}

function isNonEmptyStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.length > 0 && value.every((item) => typeof item === "string" && item.trim().length > 0);
}

function isCoverageValue(value: unknown): value is number {
  return Number.isFinite(value) && Number(value) >= 0 && Number(value) <= 100;
}

function parseSellerReportKey(key: string): { profile: SellerProfile; reportKind: SellerReportKind; marketDate: string; scope: CategoryKey | "overview" } | null {
  const alert = key.match(/^seller-alert\/daily\/(\d{4}-\d{2}-\d{2})\/([a-z0-9_]+)\.json$/);
  if (alert && (alert[2] === "overview" || categoryKeys.has(alert[2]))) return { profile: "seller_alert", reportKind: "daily", marketDate: alert[1], scope: alert[2] as CategoryKey | "overview" };
  const strategy = key.match(/^competition-strategy\/weekly\/(\d{4}-\d{2}-\d{2})\/([a-z0-9_]+)\.json$/);
  if (strategy && (strategy[2] === "overview" || categoryKeys.has(strategy[2]))) return { profile: "competition_strategy", reportKind: "weekly", marketDate: strategy[1], scope: strategy[2] as CategoryKey | "overview" };
  return null;
}

function isRank(value: unknown): value is number {
  return Number.isInteger(value) && Number(value) >= 1 && Number(value) <= 30;
}

function isValidStrategyFacts(value: unknown): value is SellerStrategyFacts {
  if (!value || typeof value !== "object") return false;
  const strategy = value as Partial<SellerStrategyFacts>;
  const rankingConcentration = strategy.rankingConcentration;
  const topStability = strategy.topStability;
  const priceBands = strategy.priceBands === null || (Array.isArray(strategy.priceBands) && strategy.priceBands.length > 0 && strategy.priceBands.every((band) => Number.isFinite(band?.lower) && band.lower >= 0 && Number.isFinite(band?.upper) && band.lower <= band.upper && Number.isInteger(band.sampleSize) && band.sampleSize > 0));
  const concentration = rankingConcentration === null || (rankingConcentration !== undefined && Number.isFinite(rankingConcentration.top10RankWeightPercent) && rankingConcentration.top10RankWeightPercent >= 0 && rankingConcentration.top10RankWeightPercent <= 100 && rankingConcentration.top10Slots === 10);
  const stability = topStability === null || (topStability !== undefined && Number.isInteger(topStability.retainedTop10) && topStability.retainedTop10 >= 0 && topStability.retainedTop10 <= 10 && Number.isInteger(topStability.entries) && topStability.entries >= 0 && topStability.entries <= 10 && Number.isInteger(topStability.exits) && topStability.exits >= 0 && topStability.exits <= 10 && topStability.retainedTop10 + topStability.entries === 10 && topStability.retainedTop10 + topStability.exits === 10 && datePattern.test(topStability.baselineDate));
  const pool = strategy.competitorPool === null || (Array.isArray(strategy.competitorPool) && strategy.competitorPool.length > 0 && new Set(strategy.competitorPool.map((entry) => entry?.asin)).size === strategy.competitorPool.length && strategy.competitorPool.every((entry) => asinPattern.test(entry?.asin ?? "") && typeof entry.title === "string" && entry.title.trim().length > 0 && Number.isInteger(entry.daysPresent) && entry.daysPresent > 0 && Number.isInteger(entry.top10Appearances) && entry.top10Appearances >= 0 && entry.top10Appearances <= entry.daysPresent && (entry.latestRank === null || isRank(entry.latestRank)) && Number.isInteger(entry.maxAbsoluteMovement) && entry.maxAbsoluteMovement >= 0 && entry.maxAbsoluteMovement <= 29 && ["medium", "low"].includes(entry.priority ?? "")));
  const specificationTrend = strategy.specificationTrend === null || (isCoverageValue(strategy.specificationTrend?.coverage) && Array.isArray(strategy.specificationTrend.observedFields) && strategy.specificationTrend.observedFields.length > 0 && strategy.specificationTrend.observedFields.every((field) => typeof field === "string" && field.trim().length > 0));
  return priceBands && concentration && stability && pool && specificationTrend;
}

function isStrategyConsistentWithEvidence(
  strategy: SellerStrategyFacts,
  categoryKey: CategoryKey | null | undefined,
  marketDate: string | undefined,
  evidence: SellerIntelligenceReport["evidence"] | undefined,
): boolean {
  const facts = [strategy.priceBands, strategy.rankingConcentration, strategy.topStability, strategy.competitorPool, strategy.specificationTrend];
  if (categoryKey == null || !evidence?.complete || evidence.completeMarketDays < 5) {
    return facts.every((fact) => fact === null);
  }
  const coverage = evidence.fieldCoverage as Partial<SellerIntelligenceReport["evidence"]["fieldCoverage"]> | null | undefined;
  if (!coverage || ![coverage.price, coverage.rating, coverage.reviews, coverage.discount, coverage.specs].every((value) => isCoverageValue(value))) return false;
  if (strategy.priceBands !== null) {
    if (coverage.price! < 80) return false;
    if (strategy.priceBands.reduce((total, band) => total + band.sampleSize, 0) > evidence.sampleSize) return false;
  }
  if (strategy.specificationTrend !== null) {
    if (coverage.specs! < 80 || strategy.specificationTrend.coverage !== coverage.specs) return false;
  }
  if (strategy.topStability !== null && (typeof marketDate !== "string" || strategy.topStability.baselineDate >= marketDate)) return false;
  if (strategy.competitorPool !== null && strategy.competitorPool.some((entry) => entry.daysPresent > evidence.completeMarketDays)) return false;
  return true;
}

export function validateSellerIntelligenceReport(
  input: unknown,
): { ok: true; report: SellerIntelligenceReport } | { ok: false; errors: string[] } {
  const report = (input ?? {}) as Partial<SellerIntelligenceReport>;
  const errors: string[] = [];

  if (report.schemaVersion !== "seller-intelligence-v1") errors.push("不支持的卖家情报报告版本");

  if (report.reportKind !== "daily" && report.reportKind !== "weekly") errors.push("报告类型无效");
  if (report.profile !== "seller_alert" && report.profile !== "competition_strategy") errors.push("报告画像无效");

  const key = String(report.key ?? "");
  const parsedKey = parseSellerReportKey(key);
  if (!parsedKey) errors.push("卖家情报报告键无效");
  if (parsedKey && (parsedKey.profile !== report.profile || parsedKey.reportKind !== report.reportKind)) errors.push("报告键必须与画像和类型一致");

  if (!datePattern.test(String(report.marketDate ?? ""))) errors.push("市场日期无效");
  if (report.categoryKey !== null && report.categoryKey !== undefined && !categories.some(({ key: categoryKey }) => categoryKey === report.categoryKey)) {
    errors.push("榜单键无效");
  }
  if (parsedKey && parsedKey.marketDate !== report.marketDate) errors.push("报告键必须与市场日期一致");
  if (parsedKey?.scope === "overview") {
    if (report.categoryKey !== null) errors.push("榜单键必须与报告范围一致");
  } else if (parsedKey && report.categoryKey !== parsedKey.scope) {
    errors.push("榜单键必须与报告范围一致");
  }
  if (typeof report.generatedAt !== "string" || Number.isNaN(Date.parse(report.generatedAt))) errors.push("生成时间无效");
  if (typeof report.generatorVersion !== "string" || !/^seller-rules-v\d+(?:\.\d+)*$/.test(report.generatorVersion)) errors.push("生成版本无效");
  if (!sha256.test(String(report.contentSha256 ?? ""))) errors.push("内容哈希无效");

  const evidence = report.evidence;
  if (
    !evidence ||
    typeof evidence.complete !== "boolean" ||
    !Number.isInteger(evidence.completeMarketDays) ||
    evidence.completeMarketDays < 0 ||
    !Number.isInteger(evidence.sampleSize) ||
    evidence.sampleSize < 0
  ) {
    errors.push("证据摘要无效");
  }

  const coverage = evidence?.fieldCoverage;
  if (
    !coverage ||
    ![coverage.price, coverage.rating, coverage.reviews, coverage.discount, coverage.specs].every((value) => isCoverageValue(value))
  ) {
    errors.push("字段覆盖率无效");
  }

  const signalInvalid = !Array.isArray(report.signals) || report.signals.some((signal) => {
    if (!signal || !["high", "watch", "activity"].includes(signal.priority) || !["rank_move", "top10_entry", "top10_exit", "top30_entry", "top30_exit", "reentry", "first_seen", "new_entry", "re_entry", "exit", "price_change", "review_momentum", "review_anomaly", "discount_change", "brand_expansion", "brand_contraction"].includes(signal.kind) || !isIntegerOrNull(signal.currentRank) || !isIntegerOrNull(signal.previousRank) || !isNonEmptyStringArray(signal.checks) || !isNonEmptyStringArray(signal.evidence)) return true;
    if (report.profile !== "seller_alert" || report.reportKind !== "daily") return true;
    if (!evidence?.complete) return true;
    const brandSignal = signal.kind === "brand_expansion" || signal.kind === "brand_contraction";
    if (brandSignal) {
      if (signal.asin !== null || typeof signal.brand !== "string" || !signal.brand.trim() || signal.brand === "Unknown" || signal.currentRank !== null || signal.previousRank !== null || !Number.isInteger(signal.currentValue) || Number(signal.currentValue) < 0 || !Number.isInteger(signal.previousValue) || Number(signal.previousValue) < 0) return true;
      const delta = Number(signal.currentValue) - Number(signal.previousValue);
      if ((signal.kind === "brand_expansion" && delta <= 0) || (signal.kind === "brand_contraction" && delta >= 0)) return true;
      return Math.abs(delta) >= 2 ? signal.priority !== "high" : signal.priority !== "activity";
    }
    if (typeof signal.asin !== "string" || !asinPattern.test(signal.asin)) return true;
    if (signal.kind === "rank_move") {
      if (!isRank(signal.currentRank) || !isRank(signal.previousRank)) return true;
      const movement = Math.abs(signal.currentRank - signal.previousRank);
      return movement === 0 || (movement >= 20 ? signal.priority !== "high" : movement >= 10 ? signal.priority !== "watch" : signal.priority !== "activity");
    }
    if (signal.kind === "top10_entry") return signal.priority !== "high" || !isRank(signal.currentRank) || signal.currentRank > 10 || (signal.previousRank !== null && (!isRank(signal.previousRank) || signal.previousRank <= 10));
    if (signal.kind === "top10_exit") return signal.priority !== "high" || (signal.currentRank !== null && (!isRank(signal.currentRank) || signal.currentRank <= 10)) || !isRank(signal.previousRank) || signal.previousRank > 10;
    if (signal.kind === "top30_entry") return signal.priority !== "activity" || !isRank(signal.currentRank) || signal.currentRank <= 10 || signal.previousRank !== null;
    if (signal.kind === "top30_exit") return signal.priority !== "activity" || signal.currentRank !== null || !isRank(signal.previousRank) || signal.previousRank <= 10;
    if (signal.kind === "reentry") return !isRank(signal.currentRank) || signal.previousRank !== null || (signal.currentRank <= 10 ? signal.priority !== "high" : signal.priority !== "watch");
    if (signal.kind === "first_seen") return signal.priority !== "activity" || !isRank(signal.currentRank) || signal.previousRank !== null;
    if (signal.kind === "new_entry") return !isRank(signal.currentRank) || signal.previousRank !== null || (signal.currentRank <= 10 ? signal.priority !== "high" : signal.priority !== "activity");
    if (signal.kind === "re_entry") return !isRank(signal.currentRank) || signal.previousRank !== null || (signal.currentRank <= 10 ? signal.priority !== "high" : signal.priority !== "watch");
    if (signal.kind === "exit") return signal.currentRank !== null || !isRank(signal.previousRank) || (signal.previousRank <= 10 ? signal.priority !== "high" : signal.priority !== "activity");
    if (signal.kind === "price_change" || signal.kind === "review_momentum" || signal.kind === "review_anomaly") return (signal.priority !== "watch" && signal.priority !== "activity") || signal.currentValue === null || signal.currentValue === undefined || signal.previousValue === null || signal.previousValue === undefined;
    return signal.priority !== "watch" || !isRank(signal.currentRank) || !isRank(signal.previousRank) || typeof signal.discountBefore !== "string" || signal.discountBefore.trim() === "" || typeof signal.discountAfter !== "string" || signal.discountAfter.trim() === "" || signal.discountBefore === signal.discountAfter;
  });
  if (signalInvalid || (!evidence?.complete && Array.isArray(report.signals) && report.signals.length > 0)) {
    errors.push("卖家信号无效");
  }

  if (report.profile === "competition_strategy" && report.reportKind === "weekly") {
    if (!isValidStrategyFacts(report.strategy) || !isStrategyConsistentWithEvidence(report.strategy, report.categoryKey, report.marketDate, evidence)) errors.push("竞争策略事实无效");
  } else if (report.strategy !== undefined) {
    errors.push("仅周度竞争策略报告可以包含策略事实");
  }

  if (
    !Array.isArray(report.sections) ||
    report.sections.length === 0 ||
    report.sections.some(
      (section) =>
        typeof section?.title !== "string" ||
        section.title.trim().length === 0 ||
        !Array.isArray(section.statements) ||
        section.statements.length === 0 ||
        section.statements.some((statement) => typeof statement !== "string" || statement.trim().length === 0),
    )
  ) {
    errors.push("报告章节无效");
  }

  if (!Array.isArray(report.limitations) || report.limitations.length === 0 || report.limitations.some((item) => typeof item !== "string" || item.trim().length === 0)) {
    errors.push("报告限制说明无效");
  }

  const publicText = [
    ...((Array.isArray(report.sections) ? report.sections.flatMap((section) => [section.title, ...section.statements]) : []) as string[]),
    ...((Array.isArray(report.limitations) ? report.limitations : []) as string[]),
    ...((Array.isArray(report.signals) ? report.signals.flatMap((signal) => [...signal.checks, ...signal.evidence]) : []) as string[]),
  ].join(" ");
  if (privateDetail.test(publicText)) errors.push("报告包含不应公开的运营信息");

  if (report.profile === "competition_strategy" && report.reportKind === "weekly" && (evidence?.completeMarketDays ?? 0) < 5 && weeklyTrendTerms.test(publicText)) {
    errors.push("完整市场日不足时不得包含周度趋势或竞争策略结论");
  }

  return errors.length ? { ok: false, errors } : { ok: true, report: report as SellerIntelligenceReport };
}

export function validateSellerIntelligenceBundle(
  input: unknown,
): { ok: true; bundle: SellerIntelligenceBundle } | { ok: false; errors: string[] } {
  const reports = (input as { reports?: unknown })?.reports;
  if (!Array.isArray(reports) || reports.length !== sellerBundleScopes.length) {
    return { ok: false, errors: [`卖家情报批次必须恰好包含 ${sellerBundleScopes.length} 份报告`] };
  }

  const validations = reports.map(validateSellerIntelligenceReport);
  if (validations.some((validation) => !validation.ok)) {
    return { ok: false, errors: ["卖家情报批次包含无效报告"] };
  }

  const validReports = validations.map((validation) => (validation as { ok: true; report: SellerIntelligenceReport }).report);
  const first = validReports[0];
  if (validReports.some((report) => report.profile !== first.profile || report.reportKind !== first.reportKind || report.marketDate !== first.marketDate)) {
    return { ok: false, errors: ["卖家情报批次的画像、类型和日期必须一致"] };
  }

  const scopes = validReports.map((report) => parseSellerReportKey(report.key)?.scope ?? null);
  if (
    scopes.some((scope) => scope === null) ||
    new Set(validReports.map((report) => report.key)).size !== sellerBundleScopes.length ||
    new Set(scopes).size !== sellerBundleScopes.length ||
    sellerBundleScopes.some((scope) => !scopes.includes(scope))
  ) {
    return { ok: false, errors: ["卖家情报批次必须包含概览和全部启用榜单范围"] };
  }

  return { ok: true, bundle: { reports: validReports } };
}
