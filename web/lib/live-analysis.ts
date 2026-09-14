import type { AnalysisReport, AnalysisReportKind } from "./analysis-report-contract.ts";
import type { CategoryKey } from "./catalog.ts";

type LiveRow = {
  key: CategoryKey;
  label: string;
  quality: { complete: boolean };
  observations: unknown[];
  priceCoverage: { percent: number };
  ratingCoverage: { percent: number };
  reviewsCoverage: { percent: number };
  comparison: { ready: boolean; largeMoves: number | null; entries: number | null; exits: number | null };
};

type LiveDashboard = {
  marketDate: string;
  observedAt: string;
  completeMarketDays: number;
  evidence: "有限" | "可用" | "充分";
  categoryRows: LiveRow[];
};

async function sha256(value: unknown) {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function buildLiveAnalysisReport(data: LiveDashboard, options: { reportKind: AnalysisReportKind; categoryKey: CategoryKey | null }): Promise<AnalysisReport> {
  const rows = options.categoryKey ? data.categoryRows.filter((row) => row.key === options.categoryKey) : data.categoryRows;
  const complete = rows.length > 0 && rows.every((row) => row.quality.complete);
  const label = options.categoryKey ? rows[0]?.label ?? "所选榜单" : "三个榜单";
  const sampleSize = rows.reduce((sum, row) => sum + row.observations.length, 0);
  const coverage = (field: "priceCoverage" | "ratingCoverage" | "reviewsCoverage") => rows.length ? Math.round(rows.reduce((sum, row) => sum + row[field].percent, 0) / rows.length * 10) / 10 : 0;
  const statements = complete
    ? [`${label} 当前数据均为完整 Top 30，可展示可验证的排名事实。`]
    : [`${label} 当前数据不完整，暂不下结论。`];
  const sections: AnalysisReport["sections"] = [{ title: "结论摘要", statements }];
  if (!complete) {
    sections.push({ title: "数据质量", statements: [`已验证观测 ${sampleSize} 条；当前仅展示质量披露和可验证的排名事实。`] });
  } else if (options.reportKind === "daily") {
    const comparable = rows.every((row) => row.comparison.ready);
    sections.push({ title: comparable ? "日度变化" : "数据质量", statements: [comparable
      ? `相邻完整市场日中，共记录 ${rows.reduce((sum, row) => sum + (row.comparison.largeMoves ?? 0), 0)} 个明显排名异动、${rows.reduce((sum, row) => sum + (row.comparison.entries ?? 0), 0)} 个新入榜和 ${rows.reduce((sum, row) => sum + (row.comparison.exits ?? 0), 0)} 个退出榜单。`
      : "缺少可比较的相邻完整市场日，暂不比较排名变化。"] });
  } else if (data.completeMarketDays >= 5) {
    sections.push({ title: "周度趋势", statements: [`已积累 ${data.completeMarketDays} 个完整市场日；趋势仅描述排名稳定性和字段覆盖的共同变化，属于非因果观察。`] });
  } else {
    sections.push({ title: "数据质量", statements: [`当前仅有 ${data.completeMarketDays} 个完整市场日，暂不下结论，不展示周度趋势或指标关联。`] });
  }
  const draft = {
    schemaVersion: "amazon-bs-analysis-report-v1" as const,
    key: `${options.reportKind}/${data.marketDate}/${options.categoryKey ?? "overview"}.json`,
    reportKind: options.reportKind,
    marketDate: data.marketDate,
    categoryKey: options.categoryKey,
    generatedAt: data.observedAt,
    generatorVersion: "rules-v1",
    evidence: { level: data.evidence, completeMarketDays: data.completeMarketDays, sampleSize, complete, fieldCoverage: { price: coverage("priceCoverage"), rating: coverage("ratingCoverage"), reviews: coverage("reviewsCoverage") } },
    sections,
  };
  return { ...draft, contentSha256: await sha256(draft) };
}
