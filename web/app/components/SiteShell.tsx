import { ShellNavigation } from "./ShellNavigation";
import { ContextLink } from "./ContextLink";

export function SiteShell({ children }: { children: React.ReactNode }) {
  return <>
    <header className="topbar">
      <ContextLink href="/" className="brand"><span className="brandMark">A</span><span>Amazon BS 市场雷达<small>市场情报</small></span></ContextLink>
      <ShellNavigation />
    </header>
    <main className="container">{children}</main>
    <footer>公开页面仅展示经过质量校验的市场信息 · 数据源：Amazon 美国站畅销榜公开页面</footer>
  </>;
}
