import { loadGardenData } from "@/lib/garden-data";
import { ProductBrowser } from "../product-browser";
import { DecisionHero } from "../../components/DecisionHero";
import { EvidenceRail } from "../../components/EvidenceRail";
export const dynamic = "force-dynamic";
export default async function GardenProducts() { const data = await loadGardenData(); return <><div className="workspaceGrid gardenWorkspaceGrid gardenCommandGrid"><div className="workspaceContext"><DecisionHero title="产品监控" summary="按榜单查看真实样本、排名变化和历史证据，同一产品可能属于多个榜单。" /></div><aside className="workspaceActions"><EvidenceRail items={[{label:'最新完整市场日',value:data.latestMarketDate??'暂无',tone:data.latestMarketDate?'good':'warning'},{label:'榜单数量',value:data.categories.length},{label:'数据状态',value:data.error?'读取失败':'可用'}]} /></aside></div>{data.error && <p role="alert">{data.error}</p>}<ProductBrowser error={data.error} categories={data.categories} /></>; }
