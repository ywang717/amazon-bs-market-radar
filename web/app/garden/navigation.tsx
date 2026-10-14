"use client";
import { usePathname } from "next/navigation";
export function GardenNavigation() {
  const pathname = usePathname();
  return <nav className="gardenTabs" aria-label="庭院与花园次级导航">{[["/garden", "市场概览"], ["/garden/products", "产品监控"], ["/garden/opportunities", "商机观察"]].map(([href,label]) => <a target="_top" key={href} href={href} aria-current={pathname === href ? "page" : undefined}>{label}</a>)}</nav>;
}
