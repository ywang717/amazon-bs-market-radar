import { loadGardenData } from "@/lib/garden-data";
import { ProductBrowser } from "../product-browser";
export const dynamic = "force-dynamic";
export default async function GardenProducts() { const data = await loadGardenData(); return <><h2>产品监控</h2><p>按榜单查看真实样本与历史变化，同一产品可能属于多个榜单。</p>{data.error && <p role="alert">{data.error}</p>}<ProductBrowser error={data.error} categories={data.categories} /></>; }
