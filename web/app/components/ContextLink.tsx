"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { pageMarketForPath, resolvePageMarketContext, resolveSegmentForCategory, serializeMarketContext } from "@/lib/market-context";

export function ContextLink({ href, children, className, target, ...props }: {
  href: string;
  children: React.ReactNode;
  className?: string;
  target?: string;
  [key: string]: unknown;
}) {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [browserSearch, setBrowserSearch] = useState("");
  useEffect(() => {
    const sync = (event?: Event) => {
      const detail = event instanceof CustomEvent && typeof event.detail?.search === "string" ? event.detail.search : window.location.search.slice(1);
      setBrowserSearch(detail.replace(/^\?/, ""));
    };
    sync();
    window.addEventListener("popstate", sync);
    window.addEventListener("market-radar:navigation", sync);
    return () => {
      window.removeEventListener("popstate", sync);
      window.removeEventListener("market-radar:navigation", sync);
    };
  }, []);
  const activeSearch = browserSearch || searchParams.toString();
  const activeParams = new URLSearchParams(activeSearch);
  const current = resolvePageMarketContext(pageMarketForPath(pathname), activeParams).context;
  const hasExplicitSegment = activeParams.has("segment");
  const targetUrl = new URL(href, "https://market-radar.local");
  const currentDate = activeParams.get("date");
  if (currentDate && !targetUrl.searchParams.has("date")) targetUrl.searchParams.set("date", currentDate);
  const targetPage = pageMarketForPath(targetUrl.pathname);
  const context = { ...current, segment: resolveSegmentForCategory(targetPage, current.category, hasExplicitSegment ? current.segment : null) };
  const query = serializeMarketContext(context, targetUrl.searchParams);
  const inheritedHref = `${targetUrl.pathname}${query ? `?${query}` : ""}${targetUrl.hash}`;
  return <Link href={inheritedHref} className={className} target={target} prefetch={false} {...props}>{children}</Link>;
}
