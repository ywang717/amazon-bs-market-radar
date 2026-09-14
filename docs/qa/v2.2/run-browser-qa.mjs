import { strict as assert } from "node:assert";
import { chromium } from "file:///C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs";

const base = "https://amazon-bs-market-radar.warrenwangyihao.chatgpt.site";
const screenshot = "C:/Users/ASUS/Documents/亚马逊bestseller榜单监控/docs/qa/v2.2/1440-alerts-sump-pumps.png";
const browser = await chromium.launch({
  headless: true,
  executablePath: "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
});

const results = {};
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await context.newPage();

async function open(path) {
  const response = await page.goto(`${base}${path}`, { waitUntil: "domcontentloaded", timeout: 60_000 });
  assert(response && response.ok(), `HTTP ${response?.status()} for ${path}`);
  await page.waitForTimeout(1_500);
  assert(!/404|page not found/i.test(await page.locator("body").innerText()), `404 body for ${path}`);
}

await open("/?category=pressure_washers&segment=machines&date=2026-08-31");
const refreshUrl = page.url();
await page.reload({ waitUntil: "domcontentloaded" });
assert.equal(page.url(), refreshUrl);
results.refresh = "PASS";

await open("/products?category=pressure_washers&segment=machines&date=2026-08-31");
await page.getByRole("link", { name: "报告", exact: true }).click();
await page.waitForURL(/\/reports\?/, { timeout: 30_000 });
await Promise.all([
  page.waitForURL(/\/products\?/, { timeout: 30_000 }),
  page.goBack(),
]);
assert.match(page.url(), /\/products\?/);
results.back = "PASS";
await Promise.all([
  page.waitForURL(/\/reports\?/, { timeout: 30_000 }),
  page.goForward(),
]);
assert.match(page.url(), /\/reports\?/);
results.forward = "PASS";

await open("/market?category=pressure_washer_accessories&segment=all&date=2026-08-31");
assert.match(page.url(), /category=pressure_washer_accessories/);
assert.match(await page.locator("body").innerText(), /高压清洗机配件/);
results.deepLink = "PASS";

await page.getByLabel("市场分类").selectOption("sump_pumps");
await page.waitForURL(/category=sump_pumps/, { timeout: 30_000 });
assert(!new URL(page.url()).searchParams.has("date"));
results.categoryDateReset = "PASS";

const tabA = await context.newPage();
const tabB = await context.newPage();
await Promise.all([
  tabA.goto(`${base}/products?category=pressure_washers&segment=machines`, { waitUntil: "domcontentloaded" }),
  tabB.goto(`${base}/products?category=pressure_washer_accessories&segment=all`, { waitUntil: "domcontentloaded" }),
]);
await Promise.all([tabA.waitForTimeout(1_500), tabB.waitForTimeout(1_500)]);
await tabA.getByLabel("市场分类").selectOption("sump_pumps");
await tabA.waitForURL(/category=sump_pumps/, { timeout: 30_000 });
assert.match(tabB.url(), /category=pressure_washer_accessories/);
results.multiTab = "PASS";

await open("/analysis?workspace=seller_alert&category=sump_pumps&segment=all");
assert.match(await page.locator("body").innerText(), /经营预警.*High \+ Watch/s);
await page.screenshot({ path: screenshot });
results.alertsScreenshot = "PASS";

const captures = [
  [1366, 768, "/?category=pressure_washers&segment=machines", "1366-overview-pressure-washers.png"],
  [1366, 768, "/products?category=sump_pumps&segment=all", "1366-products-sump-pumps.png"],
  [1366, 768, "/rankings?category=pressure_washer_accessories&segment=all", "1366-rankings-accessories.png"],
  [1366, 768, "/reports?category=pressure_washers&segment=machines", "1366-reports-pressure-washers.png"],
  [1440, 900, "/?category=sump_pumps&segment=all", "1440-overview-sump-pumps.png"],
  [1440, 900, "/market?category=pressure_washer_accessories&segment=all", "1440-market-accessories.png"],
  [1440, 900, "/brands?category=pressure_washers&segment=machines", "1440-brands-pressure-washers.png"],
  [1440, 900, "/analysis?workspace=seller_alert&category=sump_pumps&segment=all", "1440-alerts-sump-pumps.png"],
  [1920, 1080, "/?category=pressure_washer_accessories&segment=all", "1920-overview-accessories.png"],
  [1920, 1080, "/reports?category=sump_pumps&segment=all", "1920-reports-sump-pumps.png"],
];
for (const [width, height, path, name] of captures) {
  await page.setViewportSize({ width, height });
  await open(path);
  await page.screenshot({ path: `C:/Users/ASUS/Documents/亚马逊bestseller榜单监控/docs/qa/v2.2/${name}` });
}
results.productionScreenshots = captures.length;

await browser.close();
console.log(JSON.stringify(results));
