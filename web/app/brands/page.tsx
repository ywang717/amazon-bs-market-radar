import type { Metadata } from "next";
import { loadLiveDashboard } from "@/lib/live-dashboard-data";
import { buildAnalyticalCategory, buildBrandMovement, buildBrandSeatTrend, buildBrandStructure } from "@/lib/ui-intelligence";
import { MarketContext } from "../components/MarketContext";
import { PageHeader } from "../components/PageHeader";
import { DashboardDataNotices } from "../components/DashboardDataNotices";
import { marketContextLabels, resolvePageMarketContext } from "@/lib/market-context";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "品牌" };

export default async function BrandsPage({ searchParams }: { searchParams?: Promise<Record<string, string | string[] | undefined>> }) {
  const query = searchParams ? await searchParams : {};
  const { context } = resolvePageMarketContext("brands", query);
  const labels = marketContextLabels(context);
  const data = await loadLiveDashboard({ marketDate: typeof query.date === "string" ? query.date : undefined });
  const rawCategory = data.categoryRows.find((row) => row.key === context.category)!;
  const category = buildAnalyticalCategory(rawCategory, data.productMetadata, context);
  const sevenDayMovements = buildBrandSeatTrend(category.history ?? [], data.productMetadata, 7);
  const oneDayMovements = category.comparison.ready
    ? buildBrandMovement({ current: category.observations, previous: category.previousObservations ?? [], metadata: data.productMetadata }).filter(({ verified }) => verified)
    : [];
  const trendReady = (category.history?.length ?? 0) >= 8;
  const structure = buildBrandStructure(category.observations, data.productMetadata);
  const sevenDayByBrand = new Map(sevenDayMovements.map((row) => [row.brand, row]));
  const oneDayByBrand = new Map(oneDayMovements.map((row) => [row.brand, row]));
  const structureBrandNames = new Set(structure.rows.map(({ brand }) => brand));
  const movementFor = (brand: string, movements: typeof sevenDayMovements, movementByBrand: Map<string, typeof sevenDayMovements[number]>) => brand === "Unknown"
    ? null
    : brand === "其他"
      ? movements.filter(({ brand: candidate }) => !structureBrandNames.has(candidate)).reduce((sum, item) => sum + item.delta, 0)
      : movementByBrand.get(brand)?.delta ?? 0;
  const presence = structure.rows.map((row) => ({
    brand: row.brand,
    currentSeats: row.seats,
    seatShare: row.seatShare,
    oneDayDelta: category.comparison.ready ? movementFor(row.brand, oneDayMovements, oneDayByBrand) : null,
    sevenDayDelta: trendReady ? movementFor(row.brand, sevenDayMovements, sevenDayByBrand) : null,
  }));
  const primaryBrandNames = new Set(structure.rows.filter(({ brand }) => brand !== "其他" && brand !== "Unknown").map(({ brand }) => brand));
  const metadataByAsin = new Map(data.productMetadata.map((row) => [row.asin, row]));
  const maxSeats = Math.max(1, ...presence.map((row) => row.currentSeats));

  return <>
    <MarketContext marketDate={rawCategory.marketDate} validMarketDates={rawCategory.validMarketDates} context={context} page="brands" />
    <DashboardDataNotices source={data.source} metadataAvailable={data.metadataAvailable} />
    <PageHeader eyebrow="" title="品牌" description={`观察 ${labels.category} · ${labels.segment} 在 Top30 中的品牌席位、头部存在与变化。`} />
    <section className="brandPresenceSurface">
      <div className="sectionHeading"><div><h2>品牌分布</h2><p>当前席位、席位占比与 7D 有效市场日趋势</p></div></div>
      {!trendReady && <p className="sourceNotice" role="status">当前已有 {category.history?.length ?? 0} 个完整市场日；有效市场日不足，暂无法计算 7D 席位趋势。</p>}
      {presence.length ? <div className="brandBars">{presence.map((row) => <div key={row.brand}><b>{row.brand === "Unknown" ? "未知品牌" : row.brand}</b><div><i style={{ width: `${row.currentSeats / maxSeats * 100}%` }} /></div><strong>{row.currentSeats} · {row.seatShare}%</strong></div>)}</div> : <p className="mutedText">当前没有可验证品牌证据。</p>}
      <p className="metricDefinition">席位占比 = 该品牌在榜数 ÷ 当前市场全部有效席位（{structure.denominator}）。其他与未知品牌分列；未知品牌不输出扩张或收缩结论，不代表销量或市场份额。Top3 集中度：{structure.top3Concentration === null ? "—" : `${structure.top3Concentration}%`}。</p>
    </section>
    <section className="rankingSurface tableScroll"><table className="brandTable"><thead><tr><th>品牌</th><th>榜单席位</th><th>席位占比</th><th>Top10</th><th>1D</th><th>7D</th><th>平均排名</th></tr></thead><tbody>{presence.map((row) => {
      const brandRows = category.observations.filter((observation) => {
        const brand = metadataByAsin.get(observation.asin)?.normalizedBrand;
        return row.brand === "Unknown" ? !brand : row.brand === "其他" ? Boolean(brand && !primaryBrandNames.has(brand)) : brand === row.brand;
      });
      const top10 = brandRows.filter((observation) => observation.rank <= 10).length;
      const average = brandRows.length ? (brandRows.reduce((sum, observation) => sum + observation.rank, 0) / brandRows.length).toFixed(1) : "—";
      const deltaCell = (delta: number | null) => <td className={`numberCell ${delta !== null && delta > 0 ? "positive" : delta !== null && delta < 0 ? "negative" : "neutral"}`}>{delta === null ? "—" : delta > 0 ? `+${delta}` : delta}</td>;
      return <tr key={row.brand}><td><b>{row.brand === "Unknown" ? "未知品牌" : row.brand}</b></td><td className="numberCell">{row.currentSeats}</td><td className="numberCell">{row.seatShare}%</td><td className="numberCell">{top10}</td>{deltaCell(row.oneDayDelta)}{deltaCell(row.sevenDayDelta)}<td className="numberCell">{average}</td></tr>;
    })}</tbody></table></section>
  </>;
}
