import assert from "node:assert/strict";
import { register } from "node:module";
import test from "node:test";

const workerEnvironment = globalThis.__dashboardWorkerEnvironment ??= {};
register(`data:text/javascript,export async function resolve(specifier, context, nextResolve) { if (specifier === "cloudflare:workers") return { url: "data:text/javascript,export const env = globalThis.__dashboardWorkerEnvironment", shortCircuit: true }; return nextResolve(specifier, context); }`, import.meta.url);

const storedReport = {
  schemaVersion: "amazon-bs-analysis-report-v1", key: "daily/2026-08-24/overview.json", reportKind: "daily", marketDate: "2026-08-24", categoryKey: null,
  generatedAt: "2026-08-25T01:00:00Z", generatorVersion: "rules-v1", contentSha256: "a".repeat(64),
  evidence: { level: "可用", completeMarketDays: 2, sampleSize: 90, complete: true, fieldCoverage: { price: 90, rating: 90, reviews: 90 } },
  sections: [{ title: "结论摘要", statements: ["三个榜单均为完整 Top 30。"] }],
};

function environment() {
  return {
    ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) },
    DB: {
      prepare(sql) {
        let values = [];
        return { bind(...bound) { values = bound; return this; }, async first() { return sql.includes("content_json") && values[0] === storedReport.key ? { content_json: JSON.stringify(storedReport) } : null; }, async all() { return sql.includes("FROM analysis_reports") ? { results: [{ key: storedReport.key, report_kind: "daily", market_date: "2026-08-24", category_key: null, generated_at: storedReport.generatedAt, generator_version: "rules-v1", content_sha256: storedReport.contentSha256 }] } : { results: [] }; } };
      },
      async batch() { return []; },
    },
  };
}

async function request(path) {
  const env = environment(); for (const key of Reflect.ownKeys(workerEnvironment)) delete workerEnvironment[key]; Object.assign(workerEnvironment, env);
  const workerUrl = new URL("../dist/server/index.js", import.meta.url); workerUrl.searchParams.set("test", `${Date.now()}-${Math.random()}`); const { default: worker } = await import(workerUrl.href);
  return worker.fetch(new Request(`http://localhost${path}`), env, { waitUntil() {}, passThroughOnException() {} });
}

test("lists and reads only validated public online analysis reports", async () => {
  const list = await request("/api/public/analysis?kind=daily");
  assert.equal(list.status, 200);
  const listText = await list.text();
  assert.match(listText, /daily\/2026-08-24\/overview\.json/);
  assert.doesNotMatch(listText, /C:\\Users|password|SYNC_SECRET|746254487/i);

  const detail = await request("/api/public/analysis/daily/2026-08-24/overview.json");
  assert.equal(detail.status, 200);
  assert.equal((await detail.json()).key, storedReport.key);
});
