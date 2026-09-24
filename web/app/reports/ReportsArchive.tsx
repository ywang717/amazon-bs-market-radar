"use client";

import { useEffect, useState } from "react";
import { buildReportView, resolveReportArchiveState, type ReportRecord, type ReportView } from "@/lib/reports-view";
import { QualityBadge } from "../components/QualityBadge";
import { serializeMarketContext, type MarketContext } from "@/lib/market-context";

export function ReportsArchive({ context, marketDate }: { context: MarketContext; marketDate: string }) {
  const [reports, setReports] = useState<ReportView[]>([]);
  const [loadedQuery, setLoadedQuery] = useState("");
  const [errorQuery, setErrorQuery] = useState("");
  const query = serializeMarketContext(context, { date: marketDate });
  const loaded = loadedQuery === query;
  const visibleReports = loaded ? reports : [];

  useEffect(() => {
    let current = true;
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), 10_000);
    fetch(`/api/public/reports?${query}`, { signal: controller.signal })
      .then((response) => {
        if (!response.ok) throw new Error(`Report archive request failed: ${response.status}`);
        return response.json();
      })
      .then((data: { reports?: ReportRecord[] }) => { if (current) { setReports(buildReportView(data.reports ?? [])); setErrorQuery((previous) => previous === query ? "" : previous); } })
      .catch(() => { if (current) { setReports([]); setErrorQuery(query); } })
      .finally(() => { window.clearTimeout(timeout); if (current) setLoadedQuery(query); });
    return () => { current = false; window.clearTimeout(timeout); controller.abort(); };
  }, [query]);

  const dailyCount = visibleReports.filter(({ kind }) => kind === "daily").length;
  const weeklyCount = visibleReports.filter(({ kind }) => kind === "weekly").length;
  const status = resolveReportArchiveState(loaded, visibleReports.length, errorQuery === query);
  const statusLabel = status === "loading" ? "正在读取报告" : status === "ready" ? "报告可下载" : status === "error" ? "报告读取失败" : "暂无已验证报告归档";
  const badgeLabel = status === "loading" ? "正在读取" : status === "ready" ? `已同步 ${visibleReports.length} 份` : status === "error" ? "读取失败" : "暂无归档";
  const badgeTone = status === "ready" ? "good" : status === "error" ? "danger" : "warning";
  const emptyLabel = status === "loading" ? "正在读取已验证报告…" : status === "error" ? "报告服务暂时不可用，请稍后重试。" : "暂无已验证报告归档";
  return <><section className="reportSummary"><article className="panel"><span>已同步日报</span><strong>{dailyCount}</strong><small>每榜单独立 PDF</small></article><article className="panel"><span>已同步周报</span><strong>{weeklyCount}</strong><small>按榜单独立归档</small></article><article className="panel"><span>当前同步状态</span><strong className="smaller">{statusLabel}</strong><small>只展示已成功上传的 PDF</small></article></section><section id="report-archive" className="panel reportList"><div className="panelHead"><div><h2>报告归档</h2><p>报告标题包含对应市场日信息</p></div><QualityBadge tone={badgeTone}>{badgeLabel}</QualityBadge></div>{status === "ready" ? visibleReports.map((report) => <article key={report.key}><div className="pdfIcon">PDF</div><div><b>{report.label}</b><p>{report.kindLabel} · 市场日 {report.market_date}</p></div><span>{report.sizeLabel}</span><a className="downloadButton" href={report.href} target="_blank" rel="noreferrer">查看 PDF</a></article>) : <p className="emptyReports">{emptyLabel}</p>}</section></>;
}
