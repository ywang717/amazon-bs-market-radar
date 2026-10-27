"use client";

import { useEffect, useState } from "react";
import { buildReportView, readReportPayload, resolveReportArchiveState, type ReportKindFilter, type ReportView } from "@/lib/reports-view";
import { pageRows } from "@/lib/view-state";
import { isValidMarketDate } from "@/lib/public-validation";
import { QualityBadge } from "../components/QualityBadge";
import { serializeMarketContext, type MarketContext } from "@/lib/market-context";
import { useViewQuery } from "../components/useViewQuery";
import { ListPagination } from "../components/ListPagination";

export function ReportsArchive({ context, marketDate, kind }: { context: MarketContext; marketDate: string; kind: ReportKindFilter }) {
  const { params, update } = useViewQuery();
  const archiveDate = params.get("archiveDate") ?? "";
  const [reports, setReports] = useState<ReportView[]>([]);
  const [loadedQuery, setLoadedQuery] = useState("");
  const [errorQuery, setErrorQuery] = useState("");
  const [attempt, setAttempt] = useState(0);
  const queryParams = new URLSearchParams(serializeMarketContext(context, { date: marketDate, kind }));
  if (archiveDate) queryParams.set("archiveDate", archiveDate);
  const query = queryParams.toString();
  const loaded = loadedQuery === `${query}:${attempt}`;
  const visibleReports = loaded ? reports : [];
  const pagination = pageRows(visibleReports, params.get("archivePage"), 20);

  useEffect(() => {
    let current = true;
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), 10_000);
    fetch(`/api/public/reports?${query}`, { signal: controller.signal })
      .then((response) => {
        if (!response.ok) throw new Error("报告读取失败");
        return response.json();
      })
      .then((data: unknown) => { const records = readReportPayload(data); const rows = buildReportView(records); if (records.length !== rows.length) throw new Error("报告元数据异常"); if (current) { setReports(rows); setErrorQuery(""); } })
      .catch(() => { if (current) { setReports([]); setErrorQuery(query); } })
      .finally(() => { window.clearTimeout(timeout); if (current) setLoadedQuery(`${query}:${attempt}`); });
    return () => { current = false; window.clearTimeout(timeout); controller.abort(); };
  }, [query, attempt]);

  const dailyCount = visibleReports.filter(({ kind }) => kind === "daily").length;
  const weeklyCount = visibleReports.filter(({ kind }) => kind === "weekly").length;
  const status = resolveReportArchiveState(loaded, visibleReports.length, errorQuery === query);
  const statusLabel = status === "loading" ? "正在读取报告" : status === "ready" ? "报告可下载" : status === "error" ? "报告读取失败" : "暂无已验证报告归档";
  return <>
    <div className="archiveDateControls filterBar">
      <label>归档日期（独立于市场日期）<input type="date" value={isValidMarketDate(archiveDate) ? archiveDate : ""} onChange={event => update({ archiveDate: event.target.value, archivePage: null })} /></label>
      <button type="button" onClick={() => update({ archiveDate: null, archivePage: null })}>全部归档日期</button>
      <span>当前：{archiveDate || "全部历史"} · 顶部市场日期仅用于市场分析</span>
    </div>
    {archiveDate && !isValidMarketDate(archiveDate) && <p role="alert">归档日期无效，请重新选择或查看全部归档日期。</p>}
    <section className="reportSummary"><article className="panel"><span>已同步日报</span><strong>{dailyCount}</strong><small>当前归档筛选范围</small></article><article className="panel"><span>已同步周报</span><strong>{weeklyCount}</strong><small>当前归档筛选范围</small></article><article className="panel"><span>当前同步状态</span><strong className="smaller">{statusLabel}</strong><small>只展示已成功上传的 PDF</small></article></section>
    <section id="report-archive" className="panel reportList reportArchivePanel" aria-busy={!loaded}>
      <div className="panelHead"><div><h2>报告归档</h2><p>报告标题包含对应市场日信息</p></div><QualityBadge tone={status === "ready" ? "good" : status === "error" ? "danger" : "warning"}>{status === "ready" ? `已同步 ${visibleReports.length} 份` : statusLabel}</QualityBadge></div>
      {status === "ready" ? pagination.rows.map(report => <article key={report.key}><div className="pdfIcon">PDF</div><div><b>{report.label}</b><p>{report.kindLabel} · 市场日 {report.market_date} · {report.segmentLabel}</p></div><span>{report.sizeLabel}</span><a className="downloadButton" href={report.href} target="_blank" rel="noreferrer">查看 PDF</a></article>) : <p className="emptyReports" role={status === "error" ? "alert" : "status"}>{status === "loading" ? "正在读取已验证报告…" : status === "error" ? "报告服务暂时不可用，请稍后重试。" : "暂无已验证报告归档"}</p>}
      {status === "error" && <button type="button" onClick={() => setAttempt(value => value + 1)}>重试读取报告</button>}
      {status === "ready" && <ListPagination {...pagination} onPage={page => update({ archivePage: page })} label="报告归档分页" />}
    </section>
  </>;
}
