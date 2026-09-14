"use client";

import { usePathname, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { activityPriorityPresentation } from "@/lib/ui-intelligence";
import { marketContextCacheKey, pageMarketForPath, resolvePageMarketContext } from "@/lib/market-context";
import { ContextLink } from "./ContextLink";

const navigation = [
  { href: "/", label: "总览" },
  { href: "/market", label: "市场" },
  { href: "/products", label: "产品" },
  { href: "/brands", label: "品牌" },
  { href: "/rankings", label: "榜单" },
  { href: "/reports", label: "报告" },
];

type DrawerName = "activity" | "status" | null;
type DataStatusPayload = {
  marketDate: string;
  observedAt: string;
  completeMarketDays: number;
  completeCategories: number;
  evidence: string;
  classificationCoverage?: { total: number; classified: number; percent: number; unknown: number; verifiedMachines: number };
  categoryRows: Array<{
    key: string;
    quality: { observationCount: number; complete: boolean };
    priceCoverage: { percent: number };
    ratingCoverage: { percent: number };
    reviewsCoverage: { percent: number };
  }>;
};
type ActivityPayload = { marketDate: string; marketSignals: Array<{ level: "high" | "watch" | "activity"; kind: string; asin: string | null; brand?: string; title: string; currentRank: number | null; previousRank: number | null; delta: number | null; currentValue?: string | number | null; previousValue?: string | number | null }> };

export function ShellNavigation() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const context = resolvePageMarketContext(pageMarketForPath(pathname), new URLSearchParams(searchParams.toString())).context;
  const requestedDate = searchParams.get("date");
  const contextKey = marketContextCacheKey(context, { date: requestedDate });
  const [menuOpen, setMenuOpen] = useState(false);
  const [drawer, setDrawer] = useState<DrawerName>(null);
  const [dataStatusCache, setDataStatusCache] = useState<{ key: string; payload: DataStatusPayload } | null>(null);
  const [activityCache, setActivityCache] = useState<{ key: string; payload: ActivityPayload } | null>(null);
  const dataStatus = dataStatusCache?.key === contextKey ? dataStatusCache.payload : null;
  const activity = activityCache?.key === contextKey ? activityCache.payload : null;
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState(false);
  const drawerRef = useRef<HTMLElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);

  function openDrawer(name: Exclude<DrawerName, null>) {
    const cached = name === "status" ? dataStatus : activity;
    setLoadError(false);
    setLoading(!cached);
    previousFocusRef.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    setDrawer(name);
  }

  useEffect(() => {
    if (!drawer) return;
    const panel = drawerRef.current;
    panel?.querySelector<HTMLElement>("button, a")?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setDrawer(null);
      if (event.key === "Tab" && panel) {
        const focusable = [...panel.querySelectorAll<HTMLElement>("button, a[href], input, select, textarea, [tabindex]:not([tabindex='-1'])")];
        const first = focusable[0];
        const last = focusable.at(-1);
        if (!panel.contains(document.activeElement)) { event.preventDefault(); (event.shiftKey ? last : first)?.focus(); }
        else if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
      }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      previousFocusRef.current?.focus();
    };
  }, [drawer]);

  useEffect(() => {
    if (!drawer || (drawer === "status" && dataStatus) || (drawer === "activity" && activity)) return;
    const controller = new AbortController();
    const url = `/api/public/overview?category=${context.category}&segment=${context.segment}${requestedDate ? `&date=${requestedDate}` : ""}`;
    fetch(url, { signal: controller.signal })
      .then((response) => {
        if (!response.ok) throw new Error("unavailable");
        return response.json();
      })
      .then((payload) => drawer === "status" ? setDataStatusCache({ key: contextKey, payload }) : setActivityCache({ key: contextKey, payload }))
      .catch((error) => {
        if (error instanceof Error && error.name !== "AbortError") setLoadError(true);
      })
      .finally(() => setLoading(false));
    return () => controller.abort();
  }, [drawer, dataStatus, activity, context.category, context.segment, contextKey, requestedDate]);

  return <>
    <button className="mobileMenuButton" type="button" aria-label={menuOpen ? "关闭主导航" : "打开主导航"} aria-expanded={menuOpen} aria-controls="primary-navigation" onClick={() => setMenuOpen((value) => !value)}>☰</button>
    <nav id="primary-navigation" className={menuOpen ? "primaryNav open" : "primaryNav"} aria-label="主导航">
      {navigation.map(({ href, label }) => {
        const active = href === "/" ? pathname === "/" : pathname.startsWith(href);
        return <ContextLink href={href} target="_top" aria-current={active ? "page" : undefined} key={href}>{label}</ContextLink>;
      })}
    </nav>
    <div className="shellActions">
      <button className="iconAction" type="button" aria-label="市场动态" onClick={() => openDrawer("activity")}><span aria-hidden="true">♢</span><span className="actionLabel">动态</span></button>
      <button className="statusAction" type="button" aria-label="数据状态" onClick={() => openDrawer("status")}><i aria-hidden="true" />数据状态</button>
      <ContextLink className="methodologyLink" href="/methodology" target="_top"><span aria-hidden="true">?</span>方法说明</ContextLink>
    </div>
    {drawer && typeof document !== "undefined" && createPortal(<div className="drawerLayer" role="presentation" onMouseDown={(event) => {
      if (event.currentTarget === event.target) setDrawer(null);
    }}>
      <aside ref={drawerRef} className="activityDrawer" role="dialog" aria-modal="true" aria-labelledby="drawer-title">
        <div className="drawerHeader"><div><span>{drawer === "activity" ? "市场变化" : "数据质量"}</span><h2 id="drawer-title">{drawer === "activity" ? "市场动态" : "数据状态"}</h2></div><button type="button" aria-label="关闭面板" onClick={() => setDrawer(null)}>×</button></div>
        {loading && <div className="drawerSkeleton" aria-label="正在载入"><i /><i /><i /></div>}
        {loadError && <div className="drawerEmpty" role="status"><b>数据暂时无法载入</b><p>这是加载错误，不代表当前市场没有数据。请稍后重试。</p></div>}
        {drawer === "activity" ? <>
          {!loading && !loadError && (activity?.marketSignals.length ? <div className="drawerActivityList">{activity.marketSignals.slice(0, 8).map((signal) => { const priority = activityPriorityPresentation(signal.level); return <article key={`${signal.kind}-${signal.asin ?? signal.brand}`}><span className={priority.tone}>{priority.label}</span><div><b title={signal.title}>{signal.title.length > 42 ? `${signal.title.slice(0, 41)}…` : signal.title}</b><p>{signal.previousValue !== undefined ? `${signal.previousValue} → ${signal.currentValue}` : signal.previousRank === null ? `进入 #${signal.currentRank ?? "—"}` : signal.currentRank === null ? `从 #${signal.previousRank} 退出` : `#${signal.previousRank} → #${signal.currentRank}`}</p></div><time>{activity.marketDate}</time></article>; })}</div> : <div className="drawerEmpty"><b>暂无重大异常</b><p>当前没有检测到高优先级变化；普通事件仍可在市场页面查看。</p></div>)}
          <ContextLink className="drawerLink" href="/market" target="_top">查看全部市场动态 →</ContextLink>
        </> : <>
          {!loading && !loadError && dataStatus && <dl className="statusList">
            <div><dt>运行状态</dt><dd><span className="healthDot" />正常</dd></div>
            <div><dt>最近更新</dt><dd>{dataStatus.marketDate}</dd></div>
            <div><dt>完整市场日</dt><dd>{dataStatus.completeMarketDays}</dd></div>
            <div><dt>Top30 完整度</dt><dd>{dataStatus.categoryRows.find((row) => row.key === context.category)?.quality.observationCount ?? 0} / 30</dd></div>
            <div><dt>价格覆盖率</dt><dd>{dataStatus.categoryRows.find((row) => row.key === context.category)?.priceCoverage.percent ?? 0}%</dd></div>
            <div><dt>星级覆盖率</dt><dd>{dataStatus.categoryRows.find((row) => row.key === context.category)?.ratingCoverage.percent ?? 0}%</dd></div>
            <div><dt>评论数覆盖率</dt><dd>{dataStatus.categoryRows.find((row) => row.key === context.category)?.reviewsCoverage.percent ?? 0}%</dd></div>
            <div><dt>分类覆盖率</dt><dd>{dataStatus.classificationCoverage?.percent ?? 0}%</dd></div>
            <div><dt>已验证整机</dt><dd>{dataStatus.classificationCoverage?.verifiedMachines ?? 0}</dd></div>
            <div><dt>未分类商品</dt><dd>{dataStatus.classificationCoverage?.unknown ?? 0}</dd></div>
            <div><dt>分析就绪</dt><dd>{dataStatus.completeCategories === 3 ? "是" : "部分"}</dd></div>
            <div><dt>证据充分度</dt><dd>{dataStatus.evidence}</dd></div>
          </dl>}
          <ContextLink className="drawerLink" href="/insights" target="_top">查看完整数据状态 →</ContextLink>
        </>}
      </aside>
    </div>, document.body)}
  </>;
}
