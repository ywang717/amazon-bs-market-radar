import assert from "node:assert/strict";
import test from "node:test";

import * as reportsView from "../lib/reports-view.ts";

const { buildReportView } = reportsView;

test("turns uploaded report records into Chinese downloadable report rows", () => {
  const rows = buildReportView([
    { key: "daily/2026-08-12/pressure_washers.pdf", market_date: "2026-08-12", category_key: "pressure_washers", kind: "daily", title: "Pressure Washers Daily Report", byte_count: 78002 },
    { key: "weekly/2026-08-12/sump_pumps.pdf", market_date: "2026-08-12", category_key: "sump_pumps", kind: "weekly", title: "Sump Pumps Weekly Report", byte_count: 94066 },
  ]);

  assert.deepEqual(rows.map(({ label, kindLabel, href }) => ({ label, kindLabel, href })), [
    { label: "高压清洗机", kindLabel: "日报", href: "/api/public/reports/daily/2026-08-12/pressure_washers.pdf" },
    { label: "污水泵", kindLabel: "周报", href: "/api/public/reports/weekly/2026-08-12/sump_pumps.pdf" },
  ]);
  assert.equal(rows[0].sizeLabel, "76.2 KB");
});

test("ignores report records with unsafe keys or unknown categories", () => {
  const rows = buildReportView([
    { key: "../secret.pdf", market_date: "2026-08-12", category_key: "pressure_washers", kind: "daily", title: "bad", byte_count: 1 },
    { key: "daily/2026-08-12/unknown.pdf", market_date: "2026-08-12", category_key: "unknown", kind: "daily", title: "bad", byte_count: 1 },
  ]);
  assert.deepEqual(rows, []);
});

test("resolves report archive loading, empty, and ready states", () => {
  assert.equal(typeof reportsView.resolveReportArchiveState, "function");
  assert.equal(reportsView.resolveReportArchiveState(false, 0), "loading");
  assert.equal(reportsView.resolveReportArchiveState(true, 0), "empty");
  assert.equal(reportsView.resolveReportArchiveState(true, 2), "ready");
});
