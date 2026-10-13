import Link from "next/link";
import { loadGardenData } from "@/lib/garden-data";
import { PublishedReviews } from "../published-reviews";
import { ProductBrowser } from "../product-browser";
export const dynamic = "force-dynamic";
export default async function GardenOpportunities() {const data=await loadGardenData();return <><h2>商机观察</h2><p>自动初筛只发现研究线索。需求、竞争、差异化、经济性与进入风险均有可追溯证据并经人工确认后，才可列为“值得进一步验证”。</p><p className="gardenNotice">成本未知不能填零；排名不换算销量；“值得进一步验证”不代表确定盈利。</p><Link href="/garden/review">受保护核验入口 →</Link>{data.error&&<p role="alert">{data.error}</p>}<PublishedReviews/><ProductBrowser categories={data.categories} opportunities/><section className="gardenPanel"><h2>历史周报</h2>{!data.weeklyReports.length?<p>暂无已发布周报，等待有效市场数据积累。</p>:<ul>{data.weeklyReports.map(r=><li key={r.key}><a href={`/api/public/reports/${encodeURIComponent(r.key)}`}>{r.marketDate} · {r.title}</a></li>)}</ul>}</section></>;}
