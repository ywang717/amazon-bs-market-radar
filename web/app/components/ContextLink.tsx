"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
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
  const current = resolvePageMarketContext(pageMarketForPath(pathname), new URLSearchParams(searchParams.toString())).context;
  const hasExplicitSegment = searchParams.has("segment");
  const targetUrl = new URL(href, "https://market-radar.local");
  const currentDate = searchParams.get("date");
  if (currentDate && !targetUrl.searchParams.has("date")) targetUrl.searchParams.set("date", currentDate);
  const targetPage = pageMarketForPath(targetUrl.pathname);
  const context = { ...current, segment: resolveSegmentForCategory(targetPage, current.category, hasExplicitSegment ? current.segment : null) };
  const query = serializeMarketContext(context, targetUrl.searchParams);
  const inheritedHref = `${targetUrl.pathname}${query ? `?${query}` : ""}${targetUrl.hash}`;
  return <Link href={inheritedHref} className={className} target={target} prefetch={false} {...props}>{children}</Link>;
}
