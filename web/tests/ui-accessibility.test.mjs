import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

test("rank history exposes focusable points and a non-visual data equivalent", () => {
  const productPage = read("../app/products/[asin]/page.tsx");
  const dashboardData = read("../lib/dashboard-data.ts");
  assert.match(productPage, /<svg[^>]*className="rankTimelineSvg"/);
  assert.match(productPage, /className="historyPoint"[^>]*aria-label=/);
  assert.match(productPage, /className="[^"]*rankHistoryAccessible[^"]*"/);
  assert.match(productPage, /key=\{`accessible-\$\{row\.marketDate\}-\$\{row\.observation\.rank\}-\$\{index\}`\}/);
  assert.match(productPage, /reliableHistory = hasMetadata && dashboard\.metadataAvailable/);
  assert.match(productPage, /timelineHistory = reliableHistory\.length/);
  assert.match(dashboardData, /history = selectedHistory\.map/);
  assert.doesNotMatch(productPage, /history\.map\(\(\{ marketDate, observation \}\)/);
});

test("market windows only appear for real trend metrics and incomplete product sections stay hidden", () => {
  const market = read("../app/market/page.tsx");
  const productPage = read("../app/products/[asin]/page.tsx");
  assert.match(market, /view === "overview" && <section[^\n]*className="sectionBlock marketTrendSection"[^\n]*className="marketWindowBar"/);
  assert.doesNotMatch(market, /view === "movers" \|\| view === "entrants"/);
  assert.match(market, /排名变化 · 1D/);
  assert.match(productPage, /有效在榜日/);
  assert.match(productPage, /证据充分度/);
  assert.doesNotMatch(productPage, /参数待补充/);
});

test("navigation controls identify the menu and dialog focus lifecycle", () => {
  const shell = read("../app/components/ShellNavigation.tsx");
  assert.match(shell, /aria-controls="primary-navigation"/);
  assert.match(shell, /aria-label=\{menuOpen \? "关闭主导航" : "打开主导航"\}/);
  assert.match(shell, /ref=\{drawerRef\}/);
  assert.match(shell, /previousFocusRef/);
  assert.match(shell, /!panel\.contains\(document\.activeElement\)/);
});

test("market context controls are URL-local accessible selects and never use global browser storage", () => {
  const context = read("../app/components/MarketContext.tsx");
  const navigation = read("../app/components/ShellNavigation.tsx");
  const contextLink = read("../app/components/ContextLink.tsx");
  assert.match(context, /<label[^>]*>[^<]*市场/);
  assert.match(context, /<select[^>]*aria-label="市场分类"/);
  assert.match(context, /<select[^>]*aria-label="市场分群"/);
  assert.match(context, /router\.push/);
  assert.match(context, /router\.replace/);
  assert.match(context, /params\.delete\("date"\)/);
  assert.match(contextLink, /serializeMarketContext/);
  assert.match(navigation, /contextKey/);
  assert.match(navigation, /category=\$\{context\.category\}&segment=\$\{context\.segment\}/);
  assert.doesNotMatch(`${context}\n${navigation}\n${contextLink}`, /localStorage|sessionStorage|storage event/i);
});

test("context links disable Vinext prefetch while keeping context-aware client navigation", () => {
  const contextLink = read("../app/components/ContextLink.tsx");
  assert.match(contextLink, /<Link[^>]*prefetch=\{false\}/);
  assert.match(contextLink, /searchParams\.has\("segment"\)/);
  assert.match(contextLink, /hasExplicitSegment \? current\.segment : null/);
  for (const file of ["../app/analysis/page.tsx", "../app/analysis/SellerIntelligenceCenter.tsx", "../app/products/[asin]/page.tsx"]) {
    const source = read(file);
    assert.equal(source.match(/<Link\b/g)?.length ?? 0, source.match(/prefetch=\{false\}/g)?.length ?? 0, file);
  }
});

test("persistent site chrome uses Chinese presentation copy", () => {
  const navigation = read("../app/components/ShellNavigation.tsx");
  const shell = read("../app/components/SiteShell.tsx");
  const layout = read("../app/layout.tsx");
  assert.match(navigation, />数据状态<\/button>/);
  assert.match(navigation, /"市场变化" : "数据质量"/);
  assert.match(navigation, /<dt>价格覆盖率<\/dt>/);
  assert.match(navigation, /<dt>证据充分度<\/dt>/);
  assert.doesNotMatch(navigation, /MARKET INTELLIGENCE|MARKET ACTIVITY|DATA STATUS|Data status|Last Update|Evidence Quality/);
  assert.match(shell, /Amazon 美国站畅销榜公开页面/);
  assert.doesNotMatch(shell, /Best Sellers/);
  assert.doesNotMatch(layout, /Best Sellers/);
});

test("page label checks are scoped to presentation source instead of product and brand data", () => {
  const products = read("../app/products/ProductBrowser.tsx");
  const market = read("../app/market/page.tsx");
  const brands = read("../app/brands/page.tsx");
  assert.match(products, /<th>1D<\/th><th[^>]*>7D<\/th>[\s\S]*<th>评论数<\/th><th>在榜率<\/th>/);
  assert.doesNotMatch(products, /"Rising"|"New Entry"|"Falling"|<th>Reviews<\/th>|\?\? "Unknown"/);
  assert.match(market, /波动程度 ⓘ<\/dt>/);
  assert.match(market, /市场分析视图/);
  assert.match(market, /排名变化 · 1D/);
  assert.match(market, /榜单边界事件 · 1D/);
  assert.doesNotMatch(market, />Volatility ⓘ<|>Turnover ⓘ<|>New Entry<|>Market Activity</);
  assert.match(brands, /<th>品牌<\/th><th>榜单席位<\/th><th>席位占比<\/th><th>Top10<\/th><th>1D<\/th><th>7D<\/th><th>平均排名<\/th>/);
  assert.doesNotMatch(brands, /市场席位/);
  assert.match(brands, /席位占比 = 该品牌在榜数/);
  assert.match(brands, /有效市场日不足，暂无法计算 7D 席位趋势/);
  assert.doesNotMatch(brands, /Brand Presence|Avg Rank|Others \/ Unknown|\? "ACTIVE" : "EXIT"/);
});

test("reports and alerts preserve decision hierarchy and visible signal evidence", () => {
  const reports = read("../app/reports/page.tsx");
  const alerts = read("../app/analysis/SellerIntelligenceCenter.tsx");
  const signalCard = read("../app/components/SignalCard.tsx");
  assert.match(reports, /市场摘要/);
  assert.match(reports, /市场动态/);
  assert.match(reports, /watch\.slice\(0, 5\)/);
  assert.match(reports, /<details className="panel reportActivity"/);
  assert.match(alerts, /type AlertFilter = "alerts"/);
  assert.match(alerts, /filter = "alerts"/);
  assert.match(signalCard, /previousValue/);
  assert.match(signalCard, /currentValue/);
  const overview = read("../app/page.tsx");
  assert.match(overview, /marketState\.volatility === "HIGH"/);
});

test("rank delta accessibility preserves the comparison period and excludes brand seat units", () => {
  const rankDisplay = read("../app/components/RankDisplay.tsx");
  const productBrowser = read("../app/products/ProductBrowser.tsx");
  const signalCard = read("../app/components/SignalCard.tsx");
  assert.match(rankDisplay, /comparisonLabel = "较上一有效市场日"/);
  assert.match(productBrowser, /sevenDayDelta} comparisonLabel="较 7 个有效市场日前"/);
  assert.match(signalCard, /brandSeatSignal[\s\S]*个席位/);
});

test("market brands and product identity expose finalized manager-facing semantics", () => {
  const market = read("../app/market/page.tsx");
  const brands = read("../app/brands/page.tsx");
  const identity = read("../app/components/ProductIdentity.tsx");
  assert.match(market, /Top30 商品结构/);
  assert.match(market, /值得研究/);
  assert.match(market, /Top10 评论中位数/);
  assert.match(brands, /<th>1D<\/th><th>7D<\/th>/);
  assert.match(identity, /foam_cannon: "泡沫壶"/);
  assert.match(identity, /adapter_connector: "转接头"/);
  assert.match(identity, /extension_wand: "延长杆"/);
  assert.match(identity, /sewer_jetter: "管道疏通喷管"/);
});

test("legacy seller workspace receives complete V2 dark-theme overrides", () => {
  const css = read("../app/v2.css");
  assert.match(css, /\.sellerWorkspaceControls \.tabs a[\s\S]*background: var\(--surface-2\)/);
  assert.match(css, /\.sellerSignalCard p[\s\S]*color: var\(--text-2\)/);
  assert.match(css, /\.analysisDisclosure[\s\S]*color: var\(--text-3\)/);
});
