"use client";

import { useEffect, useState } from "react";
import type { AnalysisReport } from "@/lib/analysis-report-contract";
import { categories } from "@/lib/catalog";
import { marketContextLabels, serializeMarketContext, type MarketContext } from "@/lib/market-context";

type ReportListRow = Pick<AnalysisReport, "key" | "marketDate" | "categoryKey" | "generatedAt" | "generatorVersion"> & { report_kind: "daily" | "weekly" };

const labelFor = (categoryKey: string | null) => categoryKey ? categories.find(({ key }) => key === categoryKey)?.label ?? "未知榜单" : "跨榜单总览";

function ReportBody({ report, context }: { report: AnalysisReport; context: MarketContext }) {
  const labels = marketContextLabels(context);
  return <article className="panel analysisBody"><div className="panelHead"><div><h2>{report.reportKind === "daily" ? "智能日报" : "智能周报"} · {labels.category} · {labels.segment}</h2><p>市场日 {report.marketDate} · 样本 {report.evidence.sampleSize} 条 · 完整市场日 {report.evidence.completeMarketDays} 个</p></div><span className={`badge ${report.evidence.complete ? "good" : "warning"}`}>证据充分度 · {report.evidence.level}</span></div>{report.sections.map((section) => <section key={section.title}><h3>{section.title}</h3>{section.statements.map((statement) => <p key={statement}>{statement}</p>)}</section>)}<p className="analysisDisclosure">仅描述可验证数据中的观察结果，不代表因果关系。</p></article>;
}

export function AnalysisCenter({ context, marketDate }: { context: MarketContext; marketDate: string }) {
  const [mode, setMode] = useState<"live" | "archive">("live");
  const [kind, setKind] = useState<"daily" | "weekly">("daily");
  const [live, setLive] = useState<AnalysisReport | null>(null);
  const [reports, setReports] = useState<ReportListRow[]>([]);
  const [selected, setSelected] = useState<{ requestKey: string; report: AnalysisReport } | null>(null);
  const [loadedQuery, setLoadedQuery] = useState("");
  const query = serializeMarketContext(context, { date: marketDate, kind });
  const requestKey = `${mode}:${query}`;
  const loaded = loadedQuery === requestKey;
  const beginQueryChange = () => { setSelected(null); };

  useEffect(() => {
    const controller = new AbortController();
    const endpoint = mode === "live" ? `/api/public/analysis/live?${query}` : `/api/public/analysis?${query}`;
    fetch(endpoint, { signal: controller.signal }).then((response) => response.ok ? response.json() : null).then((data) => {
      if (mode === "live") setLive(data); else setReports(data?.reports ?? []);
    }).catch((error) => { if (error?.name !== "AbortError") { if (mode === "live") setLive(null); else setReports([]); } }).finally(() => { if (!controller.signal.aborted) setLoadedQuery(requestKey); });
    return () => controller.abort();
  }, [mode, query, requestKey]);

  const openReport = (key: string) => fetch(`/api/public/analysis/${key}`).then((response) => response.ok ? response.json() : null).then((report: AnalysisReport | null) => setSelected(report ? { requestKey, report } : null)).catch(() => setSelected(null));
  return <><section className="analysisControls panel"><div className="tabs"><button className={mode === "live" ? "active" : ""} onClick={() => { beginQueryChange(); setMode("live"); }}>实时解读</button><button className={mode === "archive" ? "active" : ""} onClick={() => { beginQueryChange(); setMode("archive"); }}>历史归档</button></div><label>类型<select value={kind} onChange={(event) => { beginQueryChange(); setKind(event.target.value as "daily" | "weekly"); }}><option value="daily">日报</option><option value="weekly">周报</option></select></label><span className="analysisMarketLabel">{marketContextLabels(context).category} · {marketContextLabels(context).segment}</span></section>
    {mode === "live" ? (loaded && live ? <ReportBody report={live} context={context} /> : <p className="emptyReports">{loaded ? "暂时无法生成解读。" : "正在生成实时解读…"}</p>) : <section className="panel reportList"><div className="panelHead"><div><h2>历史智能报告</h2><p>只展示当前市场已验证且不可变归档的报告</p></div></div>{loaded && reports.length ? reports.map((report) => <article key={report.key}><div className="pdfIcon">AI</div><div><b>{report.report_kind === "daily" ? "智能日报" : "智能周报"} · {labelFor(report.categoryKey)}</b><p>市场日 {report.marketDate} · 生成于 {new Date(report.generatedAt).toLocaleString("zh-CN", { hour12: false })}</p></div><button className="downloadButton" onClick={() => openReport(report.key)}>在线阅读</button></article>) : <p className="emptyReports">{loaded ? "暂无符合筛选条件的已归档智能报告。" : "正在读取历史归档…"}</p>}</section>}
    {selected?.requestKey === requestKey && <ReportBody report={selected.report} context={context} />}
  </>;
}
