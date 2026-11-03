"use client";

import { useEffect, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { formatMarketDate } from "@/lib/ui-intelligence";

export function MarketDateCalendar({ marketDate, validMarketDates }: { marketDate: string; validMarketDates: string[] }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [open, setOpen] = useState(false);
  const [month, setMonth] = useState(`${marketDate.slice(0, 7)}-01`);
  const valid = useMemo(() => new Set(validMarketDates), [validMarketDates]);
  useEffect(() => { if (!open) return; const close = (event: MouseEvent) => { const target = event.target as HTMLElement; if (!target.closest(".dateCalendar")) setOpen(false); }; const escape = (event: KeyboardEvent) => { if (event.key === "Escape") setOpen(false); }; document.addEventListener("mousedown", close); document.addEventListener("keydown", escape); return () => { document.removeEventListener("mousedown", close); document.removeEventListener("keydown", escape); }; }, [open]);
  const first = new Date(`${month}T00:00:00Z`);
  const year = first.getUTCFullYear();
  const monthIndex = first.getUTCMonth();
  const days = new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate();
  const offset = new Date(Date.UTC(year, monthIndex, 1)).getUTCDay();
  function choose(date: string) {
    if (!valid.has(date)) return;
    const params = new URLSearchParams(searchParams.toString());
    params.set("date", date);
    if (params.get("analysis_mode") === "range") params.set("range_end", date);
    router.push(`${pathname}?${params.toString()}`, { scroll: false });
    setOpen(false);
  }
  function shift(delta: number) {
    const next = new Date(Date.UTC(year, monthIndex + delta, 1));
    setMonth(`${next.getUTCFullYear()}-${String(next.getUTCMonth() + 1).padStart(2, "0")}-01`);
  }
  const previous = validMarketDates.filter((date) => date < marketDate).at(-1);
  const next = validMarketDates.find((date) => date > marketDate);
  return <div className="dateCalendar"><button type="button" className="dateCalendarTrigger" aria-expanded={open} onClick={() => setOpen((value) => !value)}>{formatMarketDate(marketDate)}⌄</button>{open && <div className="dateCalendarPopover" role="dialog" aria-label="选择市场日期"><div className="dateCalendarHeader"><button type="button" onClick={() => shift(-1)} aria-label="上个月">‹</button><strong>{year}年{monthIndex + 1}月</strong><button type="button" onClick={() => shift(1)} aria-label="下个月">›</button></div><div className="dateCalendarWeek">{["日", "一", "二", "三", "四", "五", "六"].map((day) => <span key={day}>{day}</span>)}</div><div className="dateCalendarGrid">{Array.from({ length: offset + days }, (_, index) => { if (index < offset) return <span key={`empty-${index}`} />; const day = index - offset + 1; const date = `${year}-${String(monthIndex + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`; return <button type="button" key={date} disabled={!valid.has(date)} className={date === marketDate ? "selected" : valid.has(date) ? "available" : ""} onClick={() => choose(date)}>{day}{valid.has(date) && <i aria-hidden="true" />}</button>; })}</div><div className="dateCalendarActions"><button type="button" disabled={!previous} onClick={() => previous && choose(previous)}>上一个有效日</button><button type="button" disabled={!next} onClick={() => next && choose(next)}>下一个有效日</button><button type="button" onClick={() => choose(validMarketDates.at(-1) ?? marketDate)}>最新</button></div><small>仅可选择真实有效市场日 · Pacific Time · Esc 关闭</small></div>}</div>;
}
