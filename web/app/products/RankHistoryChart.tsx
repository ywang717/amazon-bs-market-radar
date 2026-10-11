"use client";

import { useState } from "react";
import { formatExactNumber, formatPrice } from "@/lib/ui-intelligence";

type RankHistoryPoint = {
  marketDate: string;
  rank: number | null;
  delta: number | null;
  xPercent: number;
  yPercent: number | null;
  price: number | null;
  reviews: number | null;
};

type RankHistoryLabel = { marketDate: string; xPercent: number };

export function RankHistoryChart({ points, axisLabels }: { points: RankHistoryPoint[]; axisLabels: RankHistoryLabel[] }) {
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const selected = points.find((point) => point.marketDate === selectedDate && point.rank !== null) ?? null;
  const segments: RankHistoryPoint[][] = [];
  for (const [index, point] of points.entries()) {
    if (point.rank === null) continue;
    const previous = points[index - 1];
    if (!previous || previous.rank === null) segments.push([]);
    segments.at(-1)!.push(point);
  }

  return <>
    <div className="rankChartWrap"><span className="top10ZoneLabel">TOP10</span><div className="singlePointChart"><div className="axis"><span>#1</span><span>#10</span><span>#20</span><span>#30</span></div><div className="chartArea multi rankTimelineArea"><div className="top10Zone" aria-hidden="true" /><svg className="rankTimelineSvg" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">{segments.filter((segment) => segment.length > 1).map((segment, index) => <polyline key={`segment-${index}`} points={segment.map((point) => `${point.xPercent},${point.yPercent}`).join(" ")} />)}</svg>{points.map((point, index) => point.rank !== null && point.yPercent !== null ? <button type="button" className="historyPoint" aria-label={`${point.marketDate}，排名第 ${point.rank}`} aria-expanded={selectedDate === point.marketDate} aria-controls="rank-history-detail" key={`${point.marketDate}-${point.rank}-${index}`} style={{ top: `${point.yPercent}%`, left: `${point.xPercent}%` }} onClick={() => setSelectedDate((current) => current === point.marketDate ? null : point.marketDate)} title={`${point.marketDate}\n排名 #${point.rank}\n${point.delta === null || point.delta === 0 ? "—" : point.delta > 0 ? `↑${point.delta}` : `↓${Math.abs(point.delta)}`}\n${formatPrice(point.price)}\n${formatExactNumber(point.reviews)} Reviews`} /> : null)}</div></div><div className="rankTimelineDates" aria-hidden="true">{axisLabels.map((label) => <span key={label.marketDate} style={{ left: `${label.xPercent}%` }}>{label.marketDate.slice(5).replace("-", "/")}</span>)}</div></div>
    <ol className="srOnly rankHistoryAccessible" aria-label="排名历史数据">{points.flatMap((point, index) => point.rank !== null ? [<li key={`accessible-${point.marketDate}-${point.rank}-${index}`}>{point.marketDate}，排名第 {point.rank}</li>] : [])}</ol>
    {selected ? <div id="rank-history-detail" className="historyPointDetail" role="status"><b>{selected.marketDate} · 排名 #{selected.rank}</b><span>价格 {formatPrice(selected.price)} · {formatExactNumber(selected.reviews)} Reviews</span></div> : null}
  </>;
}
