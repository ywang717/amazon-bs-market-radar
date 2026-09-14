import { categories, type CategoryKey } from "./catalog.ts";

export type AnalysisReportKind = "daily" | "weekly";
export type AnalysisEvidenceLevel = "有限" | "可用" | "充分";

export type AnalysisReport = {
  schemaVersion: "amazon-bs-analysis-report-v1";
  key: string;
  reportKind: AnalysisReportKind;
  marketDate: string;
  categoryKey: CategoryKey | null;
  generatedAt: string;
  generatorVersion: string;
  contentSha256: string;
  evidence: {
    level: AnalysisEvidenceLevel;
    completeMarketDays: number;
    sampleSize: number;
    complete: boolean;
    fieldCoverage: { price: number; rating: number; reviews: number };
  };
  sections: Array<{ title: string; statements: string[] }>;
};

const keyPattern = /^(daily|weekly)\/\d{4}-\d{2}-\d{2}\/([a-z0-9_]+)\.json$/;
const sha256 = /^[a-f0-9]{64}$/i;
const privateDetail = /(?:[A-Z]:\\|\/Users\/|smtp|password|secret|authorization|@)/i;
const trendTerms = /趋势|关联|相关|因果|留存/;
const categoryKeys = new Set<string>(categories.map(({ key }) => key));

export function validateAnalysisReport(input: unknown): { ok: true; report: AnalysisReport } | { ok: false; errors: string[] } {
  const report = (input ?? {}) as Partial<AnalysisReport>;
  const errors: string[] = [];
  if (report.schemaVersion !== "amazon-bs-analysis-report-v1") errors.push("不支持的分析报告版本");
  if (!isSafeAnalysisReportKey(String(report.key ?? ""))) errors.push("报告键无效");
  if (report.reportKind !== "daily" && report.reportKind !== "weekly") errors.push("报告类型无效");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(report.marketDate ?? ""))) errors.push("市场日期无效");
  if (report.categoryKey !== null && !categoryKeys.has(String(report.categoryKey))) errors.push("榜单键无效");
  if (typeof report.generatedAt !== "string" || Number.isNaN(Date.parse(report.generatedAt))) errors.push("生成时间无效");
  if (typeof report.generatorVersion !== "string" || !/^rules-v\d+(?:\.\d+)*$/.test(report.generatorVersion)) errors.push("生成版本无效");
  if (!sha256.test(String(report.contentSha256 ?? ""))) errors.push("内容哈希无效");
  const evidence = report.evidence;
  if (!evidence || !["有限", "可用", "充分"].includes(evidence.level ?? "") || !Number.isInteger(evidence.completeMarketDays) || evidence.completeMarketDays < 0 || !Number.isInteger(evidence.sampleSize) || evidence.sampleSize < 0 || typeof evidence.complete !== "boolean") errors.push("证据摘要无效");
  const coverage = evidence?.fieldCoverage;
  if (!coverage || [coverage.price, coverage.rating, coverage.reviews].some((value) => !Number.isFinite(value) || value < 0 || value > 100)) errors.push("字段覆盖率无效");
  if (!Array.isArray(report.sections) || report.sections.length === 0 || report.sections.some((section) => typeof section?.title !== "string" || !section.title || !Array.isArray(section.statements) || section.statements.some((statement) => typeof statement !== "string" || !statement.trim()))) errors.push("报告章节无效");
  const text = Array.isArray(report.sections) ? report.sections.flatMap((section) => [section.title, ...section.statements]).join(" ") : "";
  if (privateDetail.test(text)) errors.push("报告包含不应公开的运营信息");
  if (evidence?.level === "有限" && trendTerms.test(text)) errors.push("有限证据不得包含趋势或关联结论");
  if (report.reportKind === "weekly" && evidence && evidence.completeMarketDays < 5 && trendTerms.test(text)) errors.push("完整市场日不足时不得包含周度趋势或关联结论");
  return errors.length ? { ok: false, errors } : { ok: true, report: report as AnalysisReport };
}

export function isSafeAnalysisReportKey(key: string) {
  const match = key.match(keyPattern);
  return Boolean(match && (match[2] === "overview" || categoryKeys.has(match[2])));
}
