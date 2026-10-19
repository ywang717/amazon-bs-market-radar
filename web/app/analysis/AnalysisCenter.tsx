"use client";

import { useEffect, useRef, useState } from "react";
import { validateAnalysisReport, isSafeAnalysisReportKey, type AnalysisReport } from "@/lib/analysis-report-contract";
import { categories } from "@/lib/catalog";
import { marketContextLabels, serializeMarketContext, type MarketContext } from "@/lib/market-context";

type ReportListRow = Pick<AnalysisReport, "key" | "marketDate" | "categoryKey" | "segmentKey" | "generatedAt" | "generatorVersion"> & { report_kind: "daily" | "weekly" };

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
  const [archiveError, setArchiveError] = useState(false);
  const [selected, setSelected] = useState<{ requestKey: string; report: AnalysisReport } | null>(null);
  const [loadedQuery, setLoadedQuery] = useState("");
  const [attempt, setAttempt] = useState(0);
  const [readState, setReadState] = useState<{ query: string; key: string; status: "loading" | "error" } | null>(null);
  const readSequence = useRef(0);
  const readController = useRef<AbortController | null>(null);
  const query = serializeMarketContext(context, { date: marketDate, kind });
  const requestKey = `${mode}:${query}:${attempt}`;
  const loaded = loadedQuery === requestKey;
  const beginQueryChange = () => { readSequence.current++; readController.current?.abort(); setSelected(null); setReadState(null); };

  useEffect(() => {
    let current = true;
    const reading = readController;
    const sequence = readSequence;
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), 10_000);
    const endpoint = mode === "live" ? `/api/public/analysis/live?${query}` : `/api/public/analysis?${query}`;
    fetch(endpoint, { signal: controller.signal }).then((response) => {
      if (!response.ok) throw new Error(`Analysis request failed: ${response.status}`);
      return response.json();
    }).then((data) => {
      if (!current) return;
      if (mode === "live") { const validated = validateAnalysisReport(data); if (!validated.ok) throw new Error("Invalid analysis report"); setLive(validated.report); }
      else { if (!Array.isArray(data?.reports) || data.reports.some((row: ReportListRow) => !row || typeof row.key !== "string" || !isSafeAnalysisReportKey(row.key))) throw new Error("Invalid analysis archive"); setReports(data.reports); setArchiveError(false); }
    }).catch(() => { if (current) { if (mode === "live") setLive(null); else { setReports([]); setArchiveError(true); } } }).finally(() => { window.clearTimeout(timeout); if (current) setLoadedQuery(requestKey); });
    return () => { current = false; window.clearTimeout(timeout); controller.abort(); sequence.current++; reading.current?.abort(); };
  }, [mode, query, requestKey]);

  async function openReport(key: string) {
    readController.current?.abort();
    const controller = new AbortController(); readController.current = controller;
    const sequence = ++readSequence.current;
    const timeout = window.setTimeout(() => controller.abort(), 10_000);
    setSelected(null); setReadState({ query: requestKey, key, status: "loading" });
    try {
      const response = await fetch(`/api/public/analysis/${key}`, { signal: controller.signal });
      if (!response.ok) throw new Error("Read failed");
      const validated = validateAnalysisReport(await response.json());
      if (!validated.ok) throw new Error("Invalid report");
      if (sequence === readSequence.current) { setSelected({ requestKey, report: validated.report }); setReadState(null); }
    } catch { if (sequence === readSequence.current) setReadState({ query: requestKey, key, status: "error" }); }
    finally { window.clearTimeout(timeout); }
  }

  return <><section className="analysisControls panel"><div className="tabs"><button className={mode === "live" ? "active" : ""} onClick={() => { beginQueryChange(); setMode("live"); }}>实时解读</button><button className={mode === "archive" ? "active" : ""} onClick={() => { beginQueryChange(); setMode("archive"); }}>历史归档</button></div><label>类型<select value={kind} onChange={(event) => { beginQueryChange(); setKind(event.target.value as "daily" | "weekly"); }}><option value="daily">日报</option><option value="weekly">周报</option></select></label><span className="analysisMarketLabel">{marketContextLabels(context).category} · {marketContextLabels(context).segment}</span></section>
    {mode === "live" ? (loaded && live ? <ReportBody report={live} context={context} /> : <p className="emptyReports">{loaded ? "暂时无法生成解读。" : "正在生成实时解读…"}</p>) : <section className="panel reportList"><div className="panelHead"><div><h2>历史智能报告</h2><p>只展示当前市场已验证且不可变归档的报告</p></div></div>{loaded && archiveError ? <p className="emptyReports">智能报告归档读取失败，请稍后重试。</p> : loaded && reports.length ? reports.map((report) => <article key={report.key}><div className="pdfIcon">AI</div><div><b>{report.report_kind === "daily" ? "智能日报" : "智能周报"} · {labelFor(report.categoryKey)}</b><p>市场日 {report.marketDate} · 生成于 {new Date(report.generatedAt).toLocaleString("zh-CN", { hour12: false })}</p></div><button className="downloadButton" onClick={() => openReport(report.key)}>在线阅读</button></article>) : <p className="emptyReports">{loaded ? "暂无符合筛选条件的已归档智能报告。" : "正在读取历史归档…"}</p>}</section>}
    {loaded && ((mode === "live" && !live) || (mode === "archive" && archiveError)) && <button type="button" onClick={() => { beginQueryChange(); setAttempt(value => value + 1); }}>重试读取智能报告</button>}
    {readState?.query === requestKey && <div role={readState.status === "error" ? "alert" : "status"}>{readState.status === "loading" ? "正在读取智能报告…" : <><p>智能报告读取失败，请重试。</p><button type="button" onClick={() => openReport(readState.key)}>重试在线阅读</button></>}</div>}
    {selected?.requestKey === requestKey && <ReportBody report={selected.report} context={context} />}
  </>;
}
