import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = async (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("overview uses command hero, trend rail, and evidence action zones", async () => {
  const value = await source("app/page.tsx");
  assert.match(value, /dashboardCommandHero/);
  assert.match(value, /TrendPanel/);
  assert.match(value, /dashboardEvidenceActions/);
});

test("reports and analysis expose split workspace layout hooks", async () => {
  const [reports, archive, analysis] = await Promise.all([
    source("app/reports/page.tsx"),
    source("app/reports/ReportsArchive.tsx"),
    source("app/analysis/AnalysisCenter.tsx"),
  ]);
  assert.match(reports, /reportWorkspaceGrid/);
  assert.match(reports, /reportEvidenceActions/);
  assert.match(archive, /reportArchivePanel/);
  assert.match(analysis, /analysisWorkspaceGrid/);
  assert.match(analysis, /analysisTimelineRail/);
});

test("garden pages expose the shared command and timeline layout", async () => {
  const [products, opportunities, browser, css] = await Promise.all([
    source("app/garden/products/page.tsx"),
    source("app/garden/opportunities/page.tsx"),
    source("app/garden/product-browser.tsx"),
    source("app/garden/garden.css"),
  ]);
  assert.match(products, /gardenCommandGrid/);
  assert.match(opportunities, /gardenCommandGrid/);
  assert.match(opportunities, /gardenEvidenceRail/);
  assert.match(opportunities, /gardenTimelinePanel/);
  assert.match(browser, /gardenTimelinePanel/);
  assert.match(css, /\.gardenCommandGrid/);
});
