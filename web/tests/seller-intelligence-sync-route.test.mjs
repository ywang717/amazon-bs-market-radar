import assert from "node:assert/strict";
import { register } from "node:module";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";

const workerEnvironment = globalThis.__dashboardWorkerEnvironment ??= {};
const projectRootUrl = new URL("../", import.meta.url).href;
register(`data:text/javascript,const projectRootUrl=${JSON.stringify(projectRootUrl)};export async function resolve(specifier, context, nextResolve) { if (specifier === "cloudflare:workers") return { url: "data:text/javascript,export const env = globalThis.__dashboardWorkerEnvironment", shortCircuit: true }; if (specifier.startsWith("@/")) { const path = /\\.[a-z]+$/i.test(specifier) ? specifier.slice(2) : \`\${specifier.slice(2)}.ts\`; return { url: new URL(path, projectRootUrl).href, shortCircuit: true }; } return nextResolve(specifier, context); }`, import.meta.url);

function report(overrides = {}) {
  return {
    schemaVersion: "seller-intelligence-v1",
    key: "seller-alert/daily/2026-08-24/pressure_washers.json",
    reportKind: "daily",
    profile: "seller_alert",
    marketDate: "2026-08-24",
    categoryKey: "pressure_washers",
    generatedAt: "2026-08-25T01:00:00Z",
    generatorVersion: "seller-rules-v1",
    contentSha256: "a".repeat(64),
    evidence: {
      complete: true,
      completeMarketDays: 6,
      sampleSize: 30,
      fieldCoverage: { price: 100, rating: 100, reviews: 100, discount: 100, specs: 0 },
    },
    signals: [
      {
        priority: "high",
        kind: "rank_move",
        asin: "B000000001",
        currentRank: 4,
        previousRank: 26,
        checks: ["核查价格与优惠状态"],
        evidence: ["排名由 #26 上升至 #4"],
      },
    ],
    sections: [{ title: "经营预警", statements: ["发现 1 个高优先级待核查变化。"] }],
    limitations: ["描述性观察，不代表销量或利润预测。"],
    ...overrides,
  };
}

const sellerScopes = ["overview", "pressure_washers", "sump_pumps", "pressure_washer_accessories"];

test("legacy unbound daily reports cannot bypass category receipt provenance", async () => {
  for (const payload of [report(), reportBundle()]) {
    const env = sqliteBundleEnvironment({ beforeSellerMutation(sqlite) {
      sqlite.prepare("INSERT INTO category_capture_receipts VALUES (?, ?, ?, ?)").run(
        "2026-08-24", "sump_pumps", "f".repeat(64), "2026-08-25T00:00:00Z",
      );
    } });
    const response = await request(payload, env);
    assert.equal(response.status, 409);
    assert.equal(env.sqlite.prepare("SELECT COUNT(*) AS count FROM seller_intelligence_reports").get().count, 0);
  }
});

function reportBundle(overrides = {}) {
  const profile = overrides.profile ?? "seller_alert";
  const reportKind = overrides.reportKind ?? "daily";
  const marketDate = overrides.marketDate ?? "2026-08-24";
  const prefix = profile === "seller_alert" ? "seller-alert/daily" : "competition-strategy/weekly";
  return {
    reports: sellerScopes.map((scope, index) => report({
      ...overrides,
      profile,
      reportKind,
      marketDate,
      categoryKey: scope === "overview" ? null : scope,
      key: `${prefix}/${marketDate}/${scope}.json`,
      contentSha256: String.fromCharCode(97 + index).repeat(64),
    })),
  };
}

function bundleEnvironment({ existing = new Map(), failImportBatch = false } = {}) {
  const statements = [];
  const importBatches = [];
  return {
    SYNC_SECRET: "local-secret",
    ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) },
    statements,
    importBatches,
    existing,
    DB: {
      prepare(sql) {
        let values = [];
        return {
          sql,
          get values() { return values; },
          bind(...bound) { values = bound; return this; },
          async first() {
            const stored = existing.get(values[0]);
            return stored ? { content_sha256: stored.contentSha256 } : null;
          },
          async all() { return { results: [] }; },
          async run() { statements.push({ sql, values }); return { meta: { changes: 1 } }; },
        };
      },
      async batch(batch) {
        const inserts = batch.filter((statement) => statement.sql.includes("INSERT INTO seller_intelligence_reports"));
        if (!inserts.length) return [];
        importBatches.push(inserts);
        if (failImportBatch) throw new Error("storage unavailable");
        for (const statement of inserts) {
          existing.set(statement.values[0], { contentSha256: statement.values[7] });
        }
        return inserts.map(() => ({ meta: { changes: 1 } }));
      },
    },
  };
}

function sqliteBundleEnvironment({ snapshotReceipt, existingReports = [], beforeSellerMutation = null } = {}) {
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec("CREATE TABLE snapshots (market_date TEXT PRIMARY KEY, observed_at TEXT NOT NULL, receipt_sha256 TEXT NOT NULL UNIQUE, public_status TEXT NOT NULL, complete_category_count INTEGER NOT NULL, imported_at TEXT NOT NULL)");
  sqlite.exec("CREATE TABLE seller_intelligence_reports (key TEXT PRIMARY KEY, report_kind TEXT NOT NULL, profile TEXT NOT NULL, market_date TEXT NOT NULL, category_key TEXT, generated_at TEXT NOT NULL, generator_version TEXT NOT NULL, content_sha256 TEXT NOT NULL, content_json TEXT NOT NULL, imported_at TEXT NOT NULL)");
  if (snapshotReceipt) sqlite.prepare("INSERT INTO snapshots VALUES (?, ?, ?, ?, ?, ?)").run("2026-08-24", "2026-08-25T00:00:00Z", snapshotReceipt, "ready", 3, "2026-08-25T00:00:00Z");
  for (const stored of existingReports) {
    sqlite.prepare("INSERT INTO seller_intelligence_reports VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)").run(stored.key, stored.reportKind, stored.profile, stored.marketDate, stored.categoryKey, stored.generatedAt, stored.generatorVersion, stored.contentSha256, JSON.stringify(stored), "2026-08-25T00:00:00Z");
  }
  let mutationHookPending = typeof beforeSellerMutation === "function";
  function prepare(sql) {
    let values = [];
    return {
      sql,
      bind(...bound) { values = bound; return this; },
      async first() { return sqlite.prepare(sql).get(...values) ?? null; },
      async all() { return { results: sqlite.prepare(sql).all(...values) }; },
      async run() {
        if (/^INSERT(?: OR IGNORE)? INTO seller_intelligence_reports/i.test(sql) && mutationHookPending) {
          mutationHookPending = false;
          beforeSellerMutation(sqlite);
        }
        const result = sqlite.prepare(sql).run(...values);
        return { meta: { changes: Number(result.changes) } };
      },
    };
  }
  return {
    SYNC_SECRET: "local-secret",
    ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) },
    sqlite,
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

function environment({ canonical, insertChanges = 1 } = {}) {
  const statements = [];
  return {
    SYNC_SECRET: "local-secret",
    ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) },
    statements,
    DB: {
      prepare(sql) {
        let values = [];
        return {
          sql,
          get values() {
            return values;
          },
          bind(...bound) {
            values = bound;
            return this;
          },
          async first() {
            if (sql.includes("FROM seller_intelligence_reports") && values[0] === canonical?.key) {
              return canonical;
            }
            return null;
          },
          async all() {
            return { results: [] };
          },
          async run() {
            statements.push({ sql, values });
            return { meta: { changes: insertChanges } };
          },
        };
      },
      async batch(batch) {
        statements.push(...batch);
        return [];
      },
    },
  };
}

async function request(payload, env) {
  for (const key of Reflect.ownKeys(workerEnvironment)) delete workerEnvironment[key];
  Object.assign(workerEnvironment, env);
  const routeUrl = new URL("../app/api/sync/v1/seller-intelligence/route.ts", import.meta.url);
  routeUrl.searchParams.set("test", `${Date.now()}-${Math.random()}`);
  const { POST } = await import(routeUrl.href);
  return POST(new Request("http://localhost/api/sync/v1/seller-intelligence", {
    method: "POST",
    headers: { authorization: "Bearer local-secret", "content-type": "application/json" },
    body: JSON.stringify(payload),
  }));
}

test("accepts only the matching market receipt for a scoped seller report", async () => {
  const env = sqliteBundleEnvironment({ snapshotReceipt: "mixed:2026-08-24" });
  try {
    env.sqlite.exec("CREATE TABLE category_capture_receipts (market_date TEXT,category_key TEXT,receipt_sha256 TEXT,observed_at TEXT)");
    env.sqlite.prepare("INSERT INTO category_capture_receipts VALUES (?,?,?,?)").run("2026-08-24","pressure_washers","b".repeat(64),"2026-08-25T00:00:00Z");
    const scoped={categoryKey:"pressure_washers",receiptSha256:"b".repeat(64),reports:[report()]};
    assert.equal((await request(scoped,env)).status,201);
    assert.equal((await request({...scoped,receiptSha256:"c".repeat(64)},env)).status,409);
    assert.equal(env.sqlite.prepare("SELECT count(*) n FROM seller_intelligence_reports").get().n,1);
  } finally {env.sqlite.close();}
});

test("stores a valid seller intelligence report once and returns duplicate for the same hash", async () => {
  const env = environment();
  const imported = await request(report(), env);
  assert.equal(imported.status, 201);
  assert.deepEqual(await imported.json(), {
    status: "imported",
    key: "seller-alert/daily/2026-08-24/pressure_washers.json",
  });
  assert.equal(
    env.statements.some((statement) => statement.sql.includes("INSERT OR IGNORE INTO seller_intelligence_reports") && statement.values.at(0) === "seller-alert/daily/2026-08-24/pressure_washers.json"),
    true,
  );

  const duplicate = await request(report(), environment({
    canonical: {
      key: "seller-alert/daily/2026-08-24/pressure_washers.json",
      content_sha256: "a".repeat(64),
    },
    insertChanges: 0,
  }));
  assert.equal(duplicate.status, 200);
  assert.deepEqual(await duplicate.json(), {
    status: "duplicate",
    key: "seller-alert/daily/2026-08-24/pressure_washers.json",
  });
});

test("rejects a changed body under the same immutable key", async () => {
  const response = await request(
    report({ contentSha256: "b".repeat(64) }),
    environment({
      canonical: {
        key: "seller-alert/daily/2026-08-24/pressure_washers.json",
        content_sha256: "a".repeat(64),
      },
      insertChanges: 0,
    }),
  );

  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "immutable_key_conflict" });
});

test("returns duplicate when a concurrent same-key insert wins first", async () => {
  const response = await request(
    report(),
    environment({
      canonical: {
        key: "seller-alert/daily/2026-08-24/pressure_washers.json",
        content_sha256: "a".repeat(64),
      },
      insertChanges: 0,
    }),
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    status: "duplicate",
    key: "seller-alert/daily/2026-08-24/pressure_washers.json",
  });
});

test("rejects invalid seller intelligence payloads without leaking operational details", async () => {
  const response = await request({ schemaVersion: "seller-intelligence-v1" }, environment());

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_seller_intelligence_report" });
});

test("rejects seller bundles that do not provide one coherent overview-and-three-category cohort", async () => {
  const cases = [
    { reports: null },
    { reports: reportBundle().reports.slice(0, 3) },
    { reports: [...reportBundle().reports.slice(0, 3), reportBundle().reports[2]] },
    { reports: reportBundle().reports.map((item, index) => index === 3 ? { ...item, profile: "competition_strategy" } : item) },
    { reports: reportBundle().reports.map((item, index) => index === 3 ? { ...item, reportKind: "weekly" } : item) },
    { reports: reportBundle().reports.map((item, index) => index === 3 ? { ...item, marketDate: "2026-08-25" } : item) },
    { reports: reportBundle().reports.map((item, index) => index === 3 ? { ...item, key: "seller-alert/daily/2026-08-24/not-a-scope.json" } : item) },
  ];

  for (const payload of cases) {
    const env = bundleEnvironment();
    const response = await request(payload, env);
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: "invalid_seller_intelligence_bundle" });
    assert.equal(env.importBatches.length, 0);
    assert.equal(env.existing.size, 0);
  }
});

test("imports a complete seller bundle through one atomic D1 batch", async () => {
  const env = bundleEnvironment();
  const response = await request(reportBundle(), env);

  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { status: "imported", reportCount: 4 });
  assert.equal(env.importBatches.length, 1);
  assert.equal(env.importBatches[0].length, 4);
  assert.equal(env.existing.size, 4);
});

test("treats a repeated complete seller bundle as duplicate without another write", async () => {
  const env = bundleEnvironment();
  assert.equal((await request(reportBundle(), env)).status, 201);
  const repeated = await request(reportBundle(), env);

  assert.equal(repeated.status, 200);
  assert.deepEqual(await repeated.json(), { status: "duplicate", reportCount: 4 });
  assert.equal(env.importBatches.length, 1);
  assert.equal(env.existing.size, 4);
});

test("rejects a conflicting seller bundle without writing the remaining reports", async () => {
  const payload = reportBundle();
  const env = bundleEnvironment({
    existing: new Map([[payload.reports[0].key, { contentSha256: "f".repeat(64) }]]),
  });
  const response = await request(payload, env);

  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "immutable_key_conflict" });
  assert.equal(env.importBatches.length, 0);
  assert.equal(env.existing.size, 1);
});

test("does not expose any seller bundle reports when atomic storage fails", async () => {
  const env = bundleEnvironment({ failImportBatch: true });
  const response = await request(reportBundle(), env);

  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: "sync_unavailable" });
  assert.equal(env.importBatches.length, 1);
  assert.equal(env.existing.size, 0);
});

test("atomically replaces one coherent legacy daily seller cohort for the current snapshot receipt", async () => {
  const incomingReceipt = "f".repeat(64);
  const previous = reportBundle({ contentSha256: "9".repeat(64) });
  const incoming = reportBundle();
  const env = sqliteBundleEnvironment({ snapshotReceipt: incomingReceipt, existingReports: previous.reports });

  const response = await request({ ...incoming, receiptSha256: incomingReceipt }, env);

  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { status: "imported", reportCount: 4 });
  const rows = env.sqlite.prepare("SELECT content_json FROM seller_intelligence_reports ORDER BY key").all();
  assert.equal(rows.length, 4);
  assert.equal(rows.every((row) => JSON.parse(row.content_json).receiptSha256 === incomingReceipt), true);
});

test("rejects a mixed old-receipt daily seller cohort without writing", async () => {
  const incomingReceipt = "f".repeat(64);
  const previous = reportBundle();
  const receipts = ["b", "c", "d", "e"].map((value) => value.repeat(64));
  const existingReports = previous.reports.map((item, index) => ({ ...item, receiptSha256: receipts[index] }));
  const env = sqliteBundleEnvironment({ snapshotReceipt: incomingReceipt, existingReports });

  const response = await request({ ...reportBundle(), receiptSha256: incomingReceipt }, env);

  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "immutable_key_conflict" });
  const storedReceipts = env.sqlite.prepare("SELECT content_json FROM seller_intelligence_reports ORDER BY key").all().map((row) => JSON.parse(row.content_json).receiptSha256).sort();
  assert.deepEqual(storedReceipts, receipts.sort());
});

test("rejects changed daily seller content under the same snapshot receipt", async () => {
  const receiptSha256 = "c".repeat(64);
  const previous = reportBundle();
  const existingReports = previous.reports.map((item) => ({ ...item, receiptSha256, contentSha256: "9".repeat(64) }));
  const env = sqliteBundleEnvironment({ snapshotReceipt: receiptSha256, existingReports });

  const response = await request({ ...reportBundle(), receiptSha256 }, env);

  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "immutable_key_conflict" });
  assert.equal(env.sqlite.prepare("SELECT COUNT(*) AS count FROM seller_intelligence_reports WHERE content_sha256 = ?").get("9".repeat(64)).count, 4);
});

test("does not replace daily seller reports when the snapshot receipt changes before mutation", async () => {
  const incomingReceipt = "c".repeat(64);
  const changedReceipt = "d".repeat(64);
  const previous = reportBundle();
  const env = sqliteBundleEnvironment({
    snapshotReceipt: incomingReceipt,
    existingReports: previous.reports,
    beforeSellerMutation(sqlite) { sqlite.prepare("UPDATE snapshots SET receipt_sha256 = ? WHERE market_date = ?").run(changedReceipt, "2026-08-24"); },
  });

  const response = await request({ ...reportBundle(), receiptSha256: incomingReceipt }, env);

  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "snapshot_receipt_mismatch" });
  assert.equal(env.sqlite.prepare("SELECT COUNT(*) AS count FROM seller_intelligence_reports WHERE content_json LIKE '%receiptSha256%'").get().count, 0);
});
