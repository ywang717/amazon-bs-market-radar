import assert from "node:assert/strict";
import { register } from "node:module";
import test from "node:test";
import { DatabaseSync } from "node:sqlite";

const workerEnvironment = globalThis.__dashboardWorkerEnvironment ??= {};
register(`data:text/javascript,export async function resolve(specifier, context, nextResolve) { if (specifier === "cloudflare:workers") return { url: "data:text/javascript,export const env = globalThis.__dashboardWorkerEnvironment", shortCircuit: true }; return nextResolve(specifier, context); }`, import.meta.url);

const scopes = ["overview", "pressure_washers", "sump_pumps", "pressure_washer_accessories"];

function report(scope = "overview", overrides = {}) {
  const categoryKey = scope === "overview" ? null : scope;
  return {
    schemaVersion: "amazon-bs-analysis-report-v1",
    key: `daily/2026-08-24/${scope}.json`,
    reportKind: "daily",
    marketDate: "2026-08-24",
    categoryKey,
    generatedAt: "2026-08-25T01:00:00Z",
    generatorVersion: "rules-v1",
    receiptSha256: "b".repeat(64),
    contentSha256: "a".repeat(64),
    evidence: { level: "可用", completeMarketDays: 2, sampleSize: 90, complete: true, fieldCoverage: { price: 90, rating: 90, reviews: 90 } },
    sections: [{ title: "结论摘要", statements: ["三个榜单均为完整 Top 30。"] }],
    ...overrides,
  };
}

function reportBundle(overrides = {}) {
  return { reports: scopes.map((scope, index) => report(scope, { contentSha256: String(index + 1).repeat(64), ...overrides })) };
}

function environment({ snapshotReceipt = null, existingReports = {}, beforeAnalysisMutation = null } = {}) {
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec("CREATE TABLE snapshots (market_date TEXT PRIMARY KEY, observed_at TEXT NOT NULL, receipt_sha256 TEXT NOT NULL UNIQUE, public_status TEXT NOT NULL, complete_category_count INTEGER NOT NULL, imported_at TEXT NOT NULL)");
  sqlite.exec("CREATE TABLE analysis_reports (key TEXT PRIMARY KEY, report_kind TEXT NOT NULL, market_date TEXT NOT NULL, category_key TEXT, generated_at TEXT NOT NULL, generator_version TEXT NOT NULL, content_sha256 TEXT NOT NULL, content_json TEXT NOT NULL, imported_at TEXT NOT NULL)");
  if (snapshotReceipt) sqlite.prepare("INSERT INTO snapshots VALUES (?, ?, ?, ?, ?, ?)").run("2026-08-24", "2026-08-25T00:00:00Z", snapshotReceipt, "ready", 3, "2026-08-25T00:00:00Z");
  for (const [key, stored] of Object.entries(existingReports)) {
    let parsed = {};
    try { parsed = JSON.parse(stored.content_json); } catch { parsed = {}; }
    const [reportKind, marketDate, fileName] = key.split("/");
    const scope = fileName.replace(/\.json$/, "");
    sqlite.prepare("INSERT INTO analysis_reports VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)").run(key, parsed.reportKind ?? reportKind, parsed.marketDate ?? marketDate, parsed.categoryKey ?? (scope === "overview" ? null : scope), parsed.generatedAt ?? "2026-08-25T01:00:00Z", parsed.generatorVersion ?? "rules-v1", stored.content_sha256, stored.content_json, "2026-08-25T00:00:00Z");
  }
  const mutationStatements = [];
  let mutationHookPending = typeof beforeAnalysisMutation === "function";

  function prepare(sql) {
    let values = [];
    return {
      sql,
      get values() { return values; },
      bind(...bound) { values = bound; return this; },
      async first() { return sqlite.prepare(sql).get(...values) ?? null; },
      async all() { return { results: sqlite.prepare(sql).all(...values) }; },
      async run() {
        const isAnalysisMutation = /^INSERT INTO analysis_reports/i.test(sql);
        if (isAnalysisMutation && mutationHookPending) { mutationHookPending = false; beforeAnalysisMutation(sqlite); }
        const result = sqlite.prepare(sql).run(...values);
        if (isAnalysisMutation) mutationStatements.push({ sql, values: [...values], changes: Number(result.changes) });
        return { meta: { changes: Number(result.changes) } };
      },
    };
  }

  return {
    SYNC_SECRET: "local-secret",
    ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) },
    sqlite,
    mutationStatements,
    DB: {
      prepare,
      async batch(batch) {
        sqlite.exec("BEGIN");
        try {
          const results = [];
          for (const statement of batch) results.push(await statement.run());
          sqlite.exec("COMMIT");
          return results;
        } catch (error) {
          sqlite.exec("ROLLBACK");
          throw error;
        }
      },
    },
  };
}

async function request(payload, env) {
  for (const key of Reflect.ownKeys(workerEnvironment)) delete workerEnvironment[key];
  Object.assign(workerEnvironment, env);
  const workerUrl = new URL("../dist/server/index.js", import.meta.url); workerUrl.searchParams.set("test", `${Date.now()}-${Math.random()}`);
  const { default: worker } = await import(workerUrl.href);
  return worker.fetch(new Request("http://localhost/api/sync/v1/analysis-reports", { method: "POST", headers: { authorization: "Bearer local-secret", "content-type": "application/json" }, body: JSON.stringify(payload) }), env, { waitUntil() {}, passThroughOnException() {} });
}

function storedReports(reports) {
  return Object.fromEntries(reports.map((existing) => [existing.key, { content_sha256: existing.contentSha256, content_json: JSON.stringify(existing) }]));
}

function changedRows(env) {
  return env.mutationStatements.reduce((sum, statement) => sum + statement.changes, 0);
}

test("accepts a category-bound daily report without granting an overview receipt", async () => {
  const env = environment({ snapshotReceipt: "mixed:2026-08-24" });
  try {
    env.sqlite.exec("CREATE TABLE category_capture_receipts (market_date TEXT,category_key TEXT,receipt_sha256 TEXT,observed_at TEXT)");
    env.sqlite.prepare("INSERT INTO category_capture_receipts VALUES (?,?,?,?)").run("2026-08-24","sump_pumps","b".repeat(64),"2026-08-25T00:00:00Z");
    const scoped={categoryKey:"sump_pumps",receiptSha256:"b".repeat(64),reports:[report("sump_pumps")]};
    assert.equal((await request(scoped,env)).status,201);
    assert.equal((await request({...scoped,receiptSha256:"c".repeat(64)},env)).status,409);
    assert.equal((await request(reportBundle(),env)).status,409);
    assert.equal(env.sqlite.prepare("SELECT count(*) n FROM analysis_reports").get().n,1);
  } finally {env.sqlite.close();}
});

test("archives a validated weekly analysis report without leaking operational details", async () => {
  const env = environment();
  const weekly = report("overview", { key: "weekly/2026-08-24/overview.json", reportKind: "weekly" });
  const response = await request(weekly, env);
  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { status: "imported", key: "weekly/2026-08-24/overview.json" });
  assert.equal(env.sqlite.prepare("SELECT COUNT(*) AS count FROM analysis_reports").get().count, 1);
});

test("rejects a single daily report without writing a partial cohort", async () => {
  const env = environment({ snapshotReceipt: "b".repeat(64) });
  const response = await request(report(), env);
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "daily_analysis_requires_bundle" });
  assert.equal(env.sqlite.prepare("SELECT COUNT(*) AS count FROM analysis_reports").get().count, 0);
});

test("atomically replaces a complete daily cohort when its receipt matches the current snapshot", async () => {
  const currentReceipt = "c".repeat(64);
  const previous = reportBundle({ receiptSha256: "b".repeat(64), contentSha256: "f".repeat(64) });
  const env = environment({ snapshotReceipt: currentReceipt, existingReports: storedReports(previous.reports) });
  const incoming = reportBundle({ receiptSha256: currentReceipt });

  const response = await request(incoming, env);

  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { status: "imported", marketDate: "2026-08-24", reportKind: "daily", reports: 4 });
  assert.equal(env.mutationStatements.length, 1);
  assert.equal(changedRows(env), 4);
  const rows = env.sqlite.prepare("SELECT content_json FROM analysis_reports WHERE report_kind = 'daily' ORDER BY key").all();
  assert.equal(rows.length, 4);
  assert.equal(rows.every((row) => JSON.parse(row.content_json).receiptSha256 === currentReceipt), true);
});

test("replaces an old receipt even when all content hashes happen to match", async () => {
  const currentReceipt = "c".repeat(64);
  const incoming = reportBundle({ receiptSha256: currentReceipt });
  const previous = { reports: incoming.reports.map((item) => ({ ...item, receiptSha256: "b".repeat(64) })) };
  const env = environment({ snapshotReceipt: currentReceipt, existingReports: storedReports(previous.reports) });

  const response = await request(incoming, env);

  assert.equal(response.status, 201);
  assert.equal((await response.json()).status, "imported");
  assert.equal(env.mutationStatements.length, 1);
  assert.equal(changedRows(env), 4);
  const receipts = env.sqlite.prepare("SELECT content_json FROM analysis_reports").all().map((row) => JSON.parse(row.content_json).receiptSha256);
  assert.deepEqual(new Set(receipts), new Set([currentReceipt]));
});

test("rejects a mixed old-receipt cohort without hiding the inconsistent state", async () => {
  const incomingReceipt = "f".repeat(64);
  const oldReceipts = ["b", "c", "d", "e"].map((value) => value.repeat(64));
  const mixed = reportBundle();
  mixed.reports = mixed.reports.map((item, index) => ({ ...item, receiptSha256: oldReceipts[index], contentSha256: "9".repeat(64) }));
  const env = environment({ snapshotReceipt: incomingReceipt, existingReports: storedReports(mixed.reports) });

  const response = await request(reportBundle({ receiptSha256: incomingReceipt }), env);

  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "immutable_key_conflict" });
  assert.equal(changedRows(env), 0);
  const receipts = env.sqlite.prepare("SELECT content_json FROM analysis_reports ORDER BY key").all().map((row) => JSON.parse(row.content_json).receiptSha256).sort();
  assert.deepEqual(receipts, oldReceipts.sort());
});

test("classifies malformed stored JSON as an immutable conflict without throwing or writing", async () => {
  const incomingReceipt = "c".repeat(64);
  const previous = reportBundle({ receiptSha256: "b".repeat(64), contentSha256: "f".repeat(64) });
  const existing = storedReports(previous.reports);
  existing[previous.reports[0].key] = { content_sha256: previous.reports[0].contentSha256, content_json: "not-json" };
  const env = environment({ snapshotReceipt: incomingReceipt, existingReports: existing });

  const response = await request(reportBundle({ receiptSha256: incomingReceipt }), env);

  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "immutable_key_conflict" });
  assert.equal(changedRows(env), 0);
  assert.equal(env.sqlite.prepare("SELECT content_json FROM analysis_reports WHERE key = ?").get(previous.reports[0].key).content_json, "not-json");
});

test("rejects changed content under the same current receipt", async () => {
  const currentReceipt = "c".repeat(64);
  const previous = reportBundle({ receiptSha256: currentReceipt, contentSha256: "f".repeat(64) });
  const env = environment({ snapshotReceipt: currentReceipt, existingReports: storedReports(previous.reports) });

  const response = await request(reportBundle({ receiptSha256: currentReceipt }), env);

  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "immutable_key_conflict" });
  assert.equal(changedRows(env), 0);
});

test("rejects a replacement whose receipt does not match the current snapshot", async () => {
  const env = environment({ snapshotReceipt: "b".repeat(64) });
  const response = await request(reportBundle({ receiptSha256: "c".repeat(64) }), env);
  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "snapshot_receipt_mismatch" });
  assert.equal(changedRows(env), 0);
});

test("does not write when the snapshot receipt changes immediately before the guarded mutation", async () => {
  const incomingReceipt = "c".repeat(64);
  const changedReceipt = "d".repeat(64);
  const previous = reportBundle({ receiptSha256: "b".repeat(64), contentSha256: "f".repeat(64) });
  const env = environment({
    snapshotReceipt: incomingReceipt,
    existingReports: storedReports(previous.reports),
    beforeAnalysisMutation(sqlite) { sqlite.prepare("UPDATE snapshots SET receipt_sha256 = ? WHERE market_date = ?").run(changedReceipt, "2026-08-24"); },
  });

  const response = await request(reportBundle({ receiptSha256: incomingReceipt }), env);

  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "snapshot_receipt_mismatch" });
  assert.equal(changedRows(env), 0);
  const receipts = env.sqlite.prepare("SELECT content_json FROM analysis_reports").all().map((row) => JSON.parse(row.content_json).receiptSha256);
  assert.deepEqual(new Set(receipts), new Set(["b".repeat(64)]));
});

test("returns duplicate for an unchanged complete cohort without writing", async () => {
  const currentReceipt = "c".repeat(64);
  const incoming = reportBundle({ receiptSha256: currentReceipt });
  const env = environment({ snapshotReceipt: currentReceipt, existingReports: storedReports(incoming.reports) });
  const response = await request(incoming, env);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "duplicate", marketDate: "2026-08-24", reportKind: "daily", reports: 4 });
  assert.equal(changedRows(env), 0);
});

test("a serialized same-receipt competitor cannot overwrite the winning cohort", async () => {
  const currentReceipt = "c".repeat(64);
  const previous = reportBundle({ receiptSha256: "b".repeat(64), contentSha256: "f".repeat(64) });
  const env = environment({ snapshotReceipt: currentReceipt, existingReports: storedReports(previous.reports) });
  const winner = reportBundle({ receiptSha256: currentReceipt });
  const competitor = reportBundle({ receiptSha256: currentReceipt, contentSha256: "e".repeat(64) });

  const first = await request(winner, env);
  const second = await request(competitor, env);

  assert.equal(first.status, 201);
  assert.equal(second.status, 409);
  assert.deepEqual(await second.json(), { error: "immutable_key_conflict" });
  const hashes = env.sqlite.prepare("SELECT content_sha256 FROM analysis_reports ORDER BY key").all().map((row) => row.content_sha256).sort();
  assert.deepEqual(hashes, winner.reports.map((item) => item.contentSha256).sort());
});

test("rejects an incomplete analysis cohort without writing any report", async () => {
  const payload = reportBundle();
  payload.reports.pop();
  const env = environment({ snapshotReceipt: "b".repeat(64) });
  const response = await request(payload, env);
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_analysis_report_bundle" });
  assert.equal(env.sqlite.prepare("SELECT COUNT(*) AS count FROM analysis_reports").get().count, 0);
});
