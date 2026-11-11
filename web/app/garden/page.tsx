import { loadGardenData } from "@/lib/garden-data";
import type { Metadata } from "next";
import { DecisionHero } from "../components/DecisionHero";
import { EvidenceRail } from "../components/EvidenceRail";
import { ActionDock } from "../components/ActionDock";
export const metadata: Metadata = { title: "Garden 监控", alternates: { canonical: "/garden" } };
export const dynamic = "force-dynamic";
export default async function GardenOverview() {
  const data = await loadGardenData();
  const enabled = data.categories.filter(c => c.enabled);
  const count = new Set(enabled.flatMap(c => c.products.map(p => p.asin))).size;
  const completeCount = enabled.filter(c => c.latestComplete).length;
  const status = data.error ? "读取失败" : data.latestMarketDate ? "可用" : "暂无数据";
  const summary = data.error
    ? "当前数据服务未返回完整快照；保留真实错误状态，不把读取失败解释为空市场。"
    : data.latestMarketDate
      ? `已覆盖 ${enabled.length} 个启用榜单，先从产品监控确认证据，再进入商机核验。`
      : "尚未形成可验证的花园市场快照。";
  return <>
    <section className="gardenCommandFrame" aria-label="花园市场判断台">
      <div className="gardenCommandMain">
        <DecisionHero className="gardenDecisionHero" title="今日花园市场判断" summary={summary} tone={data.error ? "warning" : data.latestMarketDate ? "positive" : "neutral"}>
          <a target="_top" href="/garden/products">查看产品监控 →</a>
          <a target="_top" href="/garden/opportunities">进入商机观察 →</a>
        </DecisionHero>
        <div className="gardenStats" aria-label="花园市场核心指标"><article><span>最新采集市场日 · 太平洋时间</span><strong>{data.latestMarketDate || "尚无数据"}</strong></article><article><span>启用榜单 / 登记榜单</span><strong>{enabled.length} / {data.categories.length}</strong></article><article><span>去重产品样本</span><strong>{count}</strong></article></div>
      </div>
      <aside className="gardenCommandSide">
        <EvidenceRail items={[
          { label: "最新采集市场日", value: data.latestMarketDate || "尚无数据", tone: data.latestMarketDate ? "good" : "warning" },
          { label: "完整榜单", value: `${completeCount} / ${enabled.length}` },
          { label: "去重产品样本", value: count },
          { label: "数据状态", value: status, tone: data.error ? "danger" : data.latestMarketDate ? "good" : "warning" },
        ]} />
        <ActionDock><a target="_top" href="/reports">查看报告归档 →</a><a target="_top" href="/insights">查看数据状态 →</a></ActionDock>
      </aside>
    </section>
    {data.error && <p role="alert" className="gardenNotice">数据暂时无法完整载入：{data.error}</p>}
    <section className="gardenPanel gardenCoveragePanel"><h2>监控覆盖与数据状态</h2><p>采集大类及已核实的一级分支各前 30 名，不代表全部商品或全市场份额。</p>{data.categories.length ? <div className="gardenTable"><table><thead><tr><th>榜单</th><th>覆盖状态</th><th>有效数据日期</th><th>完整市场日</th><th>产品数</th><th>价格范围（USD）</th></tr></thead><tbody>{data.categories.map(c => { const prices = c.products.map(p => p.price).filter((p): p is number => typeof p === "number"); return <tr key={c.key}><th><a href={c.sourceUrl} target="_blank" rel="noreferrer">{c.label}</a></th><td>{!c.enabled ? "尚未启用" : c.latestComplete ? "最近采集完整" : "采集不完整 · 待恢复"}</td><td>{c.marketDate || "—"}</td><td>{c.completeMarketDays}</td><td>{c.products.length} / 30</td><td>{prices.length ? `$${Math.min(...prices).toFixed(2)} – $${Math.max(...prices).toFixed(2)}` : "缺少价格证据"}</td></tr>; })}</tbody></table></div> : <div className="gardenEmpty"><h3>类目节点核验中</h3><p>尚无已登记榜单，不展示模拟产品或推测的市场结论。</p></div>}</section>
    <section className="gardenPanel gardenBrandPanel"><h2>样本品牌分布</h2><p>各榜单分别统计品牌席位；未知品牌单列，席位占比不等于销量或市场份额。</p><div className="gardenCards">{enabled.map(c => { const brands = new Map<string,number>(); c.products.forEach(p => {const key = p.brand || "未知品牌"; brands.set(key,(brands.get(key)||0)+1);}); return <article key={c.key}><h3>{c.label}</h3>{[...brands].sort((a,b)=>b[1]-a[1]).slice(0,5).map(([brand,n]) => <p key={brand}>{brand}<strong>{n} 席 · {c.products.length ? (100*n/c.products.length).toFixed(1) : 0}%</strong></p>)}{!brands.size && <p>等待有效样本</p>}</article>; })}</div></section>
  </>;
}
