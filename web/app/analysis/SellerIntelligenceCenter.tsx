import Link from "next/link";
import { evidenceLevel } from "@/lib/analytics";
import { categories, categoryByKey, type CategoryKey } from "@/lib/catalog";
import {
  buildLiveSellerIntelligence,
  isSafeSellerIntelligenceKey,
  listSellerIntelligenceReports,
  loadVerifiedLiveDashboardFromD1,
  readSellerIntelligenceReport,
} from "@/lib/seller-intelligence";
import type { SellerIntelligenceReport, SellerProfile, SellerSignal } from "@/lib/seller-intelligence-contract";
import { isValidAsin, isValidMarketDate } from "@/lib/public-validation";
import { marketContextLabels, serializeMarketContext, type MarketContext } from "@/lib/market-context";

type Workspace = SellerProfile | "archive";
type AlertFilter = "alerts" | "high" | "watch" | "activity" | "all";

type SellerIntelligenceCenterProps = {
  context: MarketContext;
  marketDate: string;
  workspace: Workspace;
  archiveProfile: SellerProfile;
  categoryKey: CategoryKey | null;
  date: string;
  selectedReportKey: string | null;
  alertFilter: AlertFilter;
};

type ArchivedReportRow = Awaited<ReturnType<typeof listSellerIntelligenceReports>>[number];

function readParam(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

export function parseWorkspace(value: string): Workspace {
  return value === "competition_strategy" || value === "archive" ? value : "seller_alert";
}

export function parseArchiveProfile(value: string): SellerProfile {
  return value === "competition_strategy" ? "competition_strategy" : "seller_alert";
}

export function parseCategoryKey(value: string): CategoryKey | null {
  return categories.some((category) => category.key === value) ? value as CategoryKey : null;
}

export function parseDate(value: string) {
  return isValidMarketDate(value) ? value : "";
}

function hrefFor(next: {
  workspace?: Workspace;
  archiveProfile?: SellerProfile;
  categoryKey?: CategoryKey | null;
  date?: string;
  report?: string | null;
  alertFilter?: AlertFilter;
}, context: MarketContext) {
  const params = new URLSearchParams(serializeMarketContext(context));
  params.set("workspace", next.workspace ?? "seller_alert");
  const archiveProfile = next.archiveProfile ?? "seller_alert";
  if ((next.workspace ?? "seller_alert") === "archive") {
    params.set("profile", archiveProfile);
  }
  if (next.categoryKey) params.set("category", next.categoryKey);
  if (next.date) params.set("date", next.date);
  if (next.report) params.set("report", next.report);
  if (next.alertFilter && next.alertFilter !== "alerts") params.set("alert", next.alertFilter);
  const query = params.toString();
  return query ? `/analysis?${query}` : "/analysis";
}

function labelForCategory(categoryKey: CategoryKey | null) {
  return categoryKey ? categoryByKey[categoryKey]?.label ?? "所选榜单" : "跨榜单总览";
}

function formatCoverage(value: number, fallback: string) {
  return value > 0 ? `${value}%` : fallback;
}

function signalTone(priority: SellerSignal["priority"]) {
  return priority === "high" ? "danger" : priority === "watch" ? "warning" : "info";
}

function signalLabel(signal: SellerSignal) {
  if (signal.kind === "top10_entry") return "进入 Top 10";
  if (signal.kind === "top10_exit") return "退出 Top 10";
  if (signal.kind === "top30_entry") return "新入 Top 30";
  if (signal.kind === "top30_exit") return "退出 Top 30";
  if (signal.kind === "reentry") return "重新入榜";
  if (signal.kind === "first_seen") return "首次发现";
  if (signal.kind === "new_entry") return "新入榜";
  if (signal.kind === "re_entry") return "重新入榜";
  if (signal.kind === "exit") return "退出 Top 30";
  if (signal.kind === "price_change") return "价格变化";
  if (signal.kind === "discount_change") return signal.discountAfter === "none" ? "优惠结束" : "新增或变更优惠";
  if (signal.kind === "review_momentum") return "评论增长";
  if (signal.kind === "review_anomaly") return "评论数据异常波动";
  if (signal.kind === "brand_expansion") return "品牌席位扩张";
  if (signal.kind === "brand_contraction") return "品牌席位收缩";
  return "排名异动";
}

function formatEvidenceRange(report: SellerIntelligenceReport) {
  if (report.reportKind === "daily") return `市场日 ${report.marketDate}`;
  return `截至 ${report.marketDate} 的完整市场日窗口（${report.evidence.completeMarketDays} 日）`;
}

function completenessLabel(report: SellerIntelligenceReport) {
  return report.evidence.complete ? "当前范围已验证完整" : "当前范围待补全";
}

function readSectionStatements(report: SellerIntelligenceReport, title: string) {
  return report.sections.find((section) => section.title === title)?.statements ?? [];
}

function EvidenceSummary({ report }: { report: SellerIntelligenceReport }) {
  const level = evidenceLevel(report.evidence.completeMarketDays);
  return (
    <section className="sellerSummaryBlock" aria-label="卖家结论证据边界">
      <div className="sellerSummaryGrid">
        <article className="panel">
          <span>数据范围</span>
          <strong className="smaller">{formatEvidenceRange(report)}</strong>
          <small>{labelForCategory(report.categoryKey)}</small>
        </article>
        <article className="panel">
          <span>样本量</span>
          <strong>{report.evidence.sampleSize}</strong>
          <small>仅统计可验证公开记录</small>
        </article>
        <article className="panel">
          <span>完整度</span>
          <strong className="smaller">{completenessLabel(report)}</strong>
          <small>{report.evidence.complete ? "当前范围允许描述性观察" : "当前范围暂停扩展结论"}</small>
        </article>
        <article className="panel">
          <span>证据充分度</span>
          <strong className="smaller">{level}</strong>
          <small>{report.evidence.completeMarketDays} 个完整市场日</small>
        </article>
        <article className="panel">
          <span>价格覆盖</span>
          <strong className="smaller">{formatCoverage(report.evidence.fieldCoverage.price, "待补充")}</strong>
          <small>字段缺口不作结论</small>
        </article>
        <article className="panel">
          <span>规格可见度</span>
          <strong className="smaller">{formatCoverage(report.evidence.fieldCoverage.specs, "待补充")}</strong>
          <small>缺失规格不以零值代替</small>
        </article>
      </div>
      <p className="analysisDisclosure">仅描述可验证公开事实，不代表因果关系。</p>
    </section>
  );
}

function ReportNarrative({ report }: { report: SellerIntelligenceReport }) {
  return (
    <article className="panel sellerNarrative">
      <div className="panelHead">
        <div>
          <h2>{report.profile === "seller_alert" ? "经营预警" : "竞争观察"} · {labelForCategory(report.categoryKey)}</h2>
          <p>{formatEvidenceRange(report)} · 生成于 {new Date(report.generatedAt).toLocaleString("zh-CN", { hour12: false })}</p>
        </div>
        <span className={`badge ${report.evidence.complete ? "good" : "warning"}`}>证据充分度 · {evidenceLevel(report.evidence.completeMarketDays)}</span>
      </div>
      {report.sections.map((section) => (
        <section key={section.title}>
          <h3>{section.title.replaceAll("竞争策略", "竞争观察")}</h3>
          {section.statements.map((statement) => <p key={statement}>{statement.replaceAll("竞争策略", "竞争观察")}</p>)}
        </section>
      ))}
      <section>
        <h3>限制说明</h3>
        <ul className="sellerSimpleList">
          {report.limitations.map((item) => <li key={item}>{item}</li>)}
        </ul>
      </section>
      <p className="analysisDisclosure">描述性观察，仅用于人工复核公开事实，不代表销量、利润或因果结论。</p>
    </article>
  );
}

function AlertSignals({ report, context, marketDate, filter = "alerts" }: { report: SellerIntelligenceReport; context: MarketContext; marketDate: string; filter?: AlertFilter }) {
  const signals = report.signals.filter((signal) => filter === "all" || (filter === "alerts" ? signal.priority === "high" || signal.priority === "watch" : signal.priority === filter));
  if (signals.length === 0) {
    return (
      <article className="panel sellerEmptyState" role="status">
        <h2>待核查信号</h2>
        <p>当前范围暂未形成新的高优先级信号，仍建议结合详情页与价格状态做人工巡检。</p>
      </article>
    );
  }

  return (
    <section className="sellerSignalGrid" aria-label="待核查卖家信号">
      {signals.map((signal) => (
        <article className="panel sellerSignalCard" key={`${signal.kind}-${signal.asin ?? signal.brand}-${signal.currentRank ?? "na"}`}>
          <div className="panelHead">
            <div>
              <h2>{signalLabel(signal)}</h2>
              <p>{signal.priority === "high" ? "高优先级人工核查" : signal.priority === "watch" ? "观察并人工核查" : "市场动态"}</p>
            </div>
            <span className={`badge ${signalTone(signal.priority)}`}>{signal.priority.toUpperCase()}</span>
          </div>
          <dl className="sellerMetricList">
            <div>
              <dt>ASIN</dt>
              <dd>{signal.asin && isValidAsin(signal.asin) ? <Link prefetch={false} href={`/products/${signal.asin}?${serializeMarketContext(context, { date: marketDate })}`}>{signal.asin}</Link> : signal.brand ?? "—"}</dd>
            </div>
            <div>
              <dt>当前排名</dt>
              <dd>{signal.currentRank === null ? "仅保留公开事实" : `#${signal.currentRank}`}</dd>
            </div>
            <div>
              <dt>上一排名</dt>
              <dd>{signal.previousRank === null ? "暂无可比完整市场日" : `#${signal.previousRank}`}</dd>
            </div>
          </dl>
          {signal.previousValue !== undefined && signal.currentValue !== undefined && <p className="signalValueChange"><b>{String(signal.previousValue)}</b> → <b>{String(signal.currentValue)}</b></p>}
          <details className="signalEvidence">
            <summary>证据与核查项</summary>
            <h3>证据</h3>
            <ul className="sellerSimpleList">
              {signal.evidence.map((item) => <li key={item}>{item}</li>)}
            </ul>
          <section>
            <h3>建议核查项</h3>
            <ul className="sellerSimpleList">
              {signal.checks.map((item) => <li key={item}>{item}</li>)}
            </ul>
          </section>
          </details>
        </article>
      ))}
    </section>
  );
}

function StrategyWorkspace({ report }: { report: SellerIntelligenceReport }) {
  if (report.evidence.completeMarketDays < 5) {
    return (
      <article className="panel sellerEmptyState" role="status">
        <h2>竞争观察</h2>
        <p>数据积累中，暂不输出稳定趋势。</p>
        <p>完整市场日不足五天时，仅保留质量披露与公开排名事实。</p>
      </article>
    );
  }

  if (!report.evidence.complete) {
    const qualityStatements = readSectionStatements(report, "数据质量");
    return (
      <article className="panel sellerEmptyState" role="status">
        <h2>竞争观察</h2>
        {(qualityStatements.length ? qualityStatements : ["当前数据不完整，暂不下结论。"]).map((statement) => <p key={statement}>{statement}</p>)}
      </article>
    );
  }

  const strategy = report.strategy;
  const priceBand = strategy?.priceBands;
  const rankingConcentration = strategy?.rankingConcentration;
  const topStability = strategy?.topStability;
  const competitorPool = strategy?.competitorPool;
  const specificationTrend = strategy?.specificationTrend;

  return (
    <section className="sellerSignalGrid" aria-label="竞争观察卡片">
      <article className="panel sellerSignalCard">
        <h2>价格带观察</h2>
        {priceBand ? <ul className="sellerSimpleList">{priceBand.map((band) => <li key={`${band.lower}-${band.upper}`}>${band.lower}–${band.upper} · {band.sampleSize} 个可验证样本</li>)}</ul> : <p>价格字段覆盖不足 80% 或尚未达到五个完整市场日，暂不输出价格带观察。</p>}
      </article>
      <article className="panel sellerSignalCard">
        <h2>排名集中度</h2>
        {rankingConcentration ? <p>Top 10 名次权重占比 {rankingConcentration.top10RankWeightPercent}%（{rankingConcentration.top10Slots} 个席位）；仅反映榜单产品占位，不代表销量或市场份额。</p> : <p>完整市场日不足五天，暂不输出排名集中度。</p>}
      </article>
      <article className="panel sellerSignalCard">
        <h2>头部稳定性</h2>
        {topStability ? <p>与 {topStability.baselineDate} 相比，Top 10 留存 {topStability.retainedTop10} 个席位，新入 Top 10 {topStability.entries} 个、退出 Top 10 {topStability.exits} 个。</p> : <p>当前缺少相邻完整市场日，暂不输出头部稳定性。</p>}
      </article>
      <article className="panel sellerSignalCard">
        <h2>核心竞品池</h2>
        {competitorPool ? <ul className="sellerSimpleList">{competitorPool.slice(0, 8).map((entry) => <li key={entry.asin}>{entry.asin} · 最近 #{entry.latestRank ?? "—"} · 连续/在榜 {entry.daysPresent} 日 · {entry.priority === "medium" ? "中优先级观察" : "低优先级跟踪"}</li>)}</ul> : <p>完整市场日不足五天，暂不输出核心竞品池。</p>}
      </article>
      <article className="panel sellerSignalCard">
        <h2>规格覆盖与趋势</h2>
        {specificationTrend ? <p>标题中明确规格覆盖 {specificationTrend.coverage}%；可验证字段：{specificationTrend.observedFields.join("、")}。</p> : <p>规格字段覆盖不足 80% 或尚未达到五个完整市场日，暂不输出规格趋势。</p>}
      </article>
    </section>
  );
}

function ArchiveWorkspace({
  context,
  profile,
  categoryKey,
  date,
  reports,
  selected,
}: {
  context: MarketContext;
  profile: SellerProfile;
  categoryKey: CategoryKey | null;
  date: string;
  reports: ArchivedReportRow[];
  selected: SellerIntelligenceReport | null;
}) {
  return (
    <>
      <section className="panel reportList sellerArchiveList">
        <div className="panelHead">
          <div>
            <h2>历史归档</h2>
            <p>只显示已验证且不可变的卖家情报报告。</p>
          </div>
          <span className="badge info">{profile === "seller_alert" ? "经营预警归档" : "竞争观察归档"}</span>
        </div>
        {reports.length ? reports.map((report) => (
          <article key={report.key}>
            <div className="pdfIcon">{report.profile === "seller_alert" ? "AL" : "ST"}</div>
            <div>
              <b>{report.profile === "seller_alert" ? "经营预警" : "竞争观察"} · {labelForCategory(report.category_key as CategoryKey | null)}</b>
              <p>{report.profile === "seller_alert" ? "经营预警" : "竞争观察"} · {labelForCategory(report.category_key as CategoryKey | null)} · {report.market_date}</p>
              <p>生成于 {new Date(report.generated_at).toLocaleString("zh-CN", { hour12: false })}</p>
            </div>
            <Link
              prefetch={false}
              className="downloadButton"
              aria-current={selected?.key === report.key ? "page" : undefined}
              href={hrefFor({ workspace: "archive", archiveProfile: profile, categoryKey, date, report: report.key }, context)}
            >
              在线阅读
            </Link>
          </article>
        )) : <p className="emptyReports">暂无符合筛选条件的卖家归档。</p>}
      </section>
      {selected && <EvidenceSummary report={selected} />}
      {selected?.profile === "seller_alert" && <AlertSignals report={selected} context={context} marketDate={selected.marketDate} />}
      {selected?.profile === "competition_strategy" && <StrategyWorkspace report={selected} />}
      {selected && <ReportNarrative report={selected} />}
    </>
  );
}

export async function SellerIntelligenceCenter({
  context,
  marketDate,
  workspace,
  archiveProfile,
  categoryKey,
  date,
  selectedReportKey,
  alertFilter,
}: SellerIntelligenceCenterProps) {
  const liveCategory = workspace === "seller_alert"
    ? (categoryKey ?? categories[0].key)
    : categoryKey;

  let liveReport: SellerIntelligenceReport | null = null;
  let archivedReports: ArchivedReportRow[] = [];
  let selectedArchivedReport: SellerIntelligenceReport | null = null;

  if (workspace === "archive") {
    try {
      archivedReports = await listSellerIntelligenceReports({
        profile: archiveProfile,
        category: categoryKey,
        date: date || null,
      });
      if (selectedReportKey && isSafeSellerIntelligenceKey(selectedReportKey) && archivedReports.some((report) => report.key === selectedReportKey)) {
        const detail = await readSellerIntelligenceReport(selectedReportKey);
        selectedArchivedReport = detail.status === "found" ? detail.report : null;
      }
    } catch {
      archivedReports = [];
    }
  } else {
    try {
      const dashboard = await loadVerifiedLiveDashboardFromD1(marketDate);
      liveReport = await buildLiveSellerIntelligence(dashboard, {
        profile: workspace,
        categoryKey: liveCategory,
        context,
      });
    } catch {
      liveReport = null;
    }
  }

  return (
    <>
      <section className="analysisControls panel sellerWorkspaceControls" aria-label="卖家工作区">
        <nav className="tabs" aria-label="卖家情报工作区">
          <Link prefetch={false} aria-current={workspace === "seller_alert" ? "page" : undefined} className={workspace === "seller_alert" ? "active" : ""} href={hrefFor({ workspace: "seller_alert", categoryKey: liveCategory ?? categories[0].key, date: marketDate }, context)}>经营预警</Link>
          <Link prefetch={false} aria-current={workspace === "competition_strategy" ? "page" : undefined} className={workspace === "competition_strategy" ? "active" : ""} href={hrefFor({ workspace: "competition_strategy", categoryKey, date: marketDate }, context)}>竞争观察</Link>
          <Link prefetch={false} aria-current={workspace === "archive" ? "page" : undefined} className={workspace === "archive" ? "active" : ""} href={hrefFor({ workspace: "archive", archiveProfile, categoryKey, date }, context)}>历史归档</Link>
        </nav>
        <form className="sellerFilterGrid" action="/analysis">
          <input type="hidden" name="workspace" value={workspace} />
          <input type="hidden" name="category" value={context.category} />
          <input type="hidden" name="segment" value={context.segment} />
          {workspace !== "archive" && <input type="hidden" name="date" value={marketDate} />}
          <span className="analysisMarketLabel">{marketContextLabels(context).category} · {marketContextLabels(context).segment}</span>
          {workspace === "archive" && (
            <>
              <label>
                归档画像
                <select name="profile" defaultValue={archiveProfile}>
                  <option value="seller_alert">经营预警</option>
                  <option value="competition_strategy">竞争观察</option>
                </select>
              </label>
              <label>
                市场日
                <input type="date" name="date" defaultValue={date} />
              </label>
            </>
          )}
          <button className="downloadButton sellerFilterButton" type="submit">应用筛选</button>
        </form>
      </section>

      {workspace === "archive" ? (
        <ArchiveWorkspace
          profile={archiveProfile}
          context={context}
          categoryKey={categoryKey}
          date={date}
          reports={archivedReports}
          selected={selectedArchivedReport}
        />
      ) : liveReport ? (
        <>
          <EvidenceSummary report={liveReport} />
          {workspace === "seller_alert" && <nav className="alertFilterTabs" aria-label="预警优先级筛选">
            {(["alerts", "high", "watch", "activity"] as const).map((filter) => <Link prefetch={false} aria-current={alertFilter === filter ? "page" : undefined} className={alertFilter === filter ? "active" : ""} href={hrefFor({ workspace: "seller_alert", categoryKey: liveCategory, date: marketDate, alertFilter: filter }, context)} key={filter}>{filter === "alerts" ? "High + Watch" : filter === "high" ? "High" : filter === "watch" ? "Watch" : "市场动态"}</Link>)}
          </nav>}
          {workspace === "seller_alert" ? <AlertSignals report={liveReport} context={context} marketDate={marketDate} filter={alertFilter} /> : <StrategyWorkspace report={liveReport} />}
          <ReportNarrative report={liveReport} />
        </>
      ) : (
        <article className="panel sellerEmptyState" role="status">
          <h2>{workspace === "seller_alert" ? "经营预警" : "竞争观察"}</h2>
          <p>当前暂时无法读取卖家情报，请稍后重试。</p>
        </article>
      )}
    </>
  );
}

export function parseAnalysisSearchParams(searchParams: Record<string, string | string[] | undefined>) {
  const workspace = parseWorkspace(readParam(searchParams.workspace));
  const archiveProfile = parseArchiveProfile(readParam(searchParams.profile));
  const categoryKey = parseCategoryKey(readParam(searchParams.category));
  const date = parseDate(readParam(searchParams.date));
  const reportCandidate = readParam(searchParams.report);
  const alertCandidate = readParam(searchParams.alert);
  return {
    workspace,
    archiveProfile,
    categoryKey,
    date,
    selectedReportKey: reportCandidate && isSafeSellerIntelligenceKey(reportCandidate) ? reportCandidate : null,
    alertFilter: alertCandidate === "high" || alertCandidate === "watch" || alertCandidate === "activity" || alertCandidate === "all" ? alertCandidate : "alerts" as AlertFilter,
  };
}
