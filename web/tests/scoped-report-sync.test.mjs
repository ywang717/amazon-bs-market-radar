import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { storeCategoryReport } from '../lib/scoped-report-sync.ts';

function environment() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(`CREATE TABLE category_capture_receipts (market_date TEXT, category_key TEXT, receipt_sha256 TEXT);
    CREATE TABLE snapshots (market_date TEXT, receipt_sha256 TEXT);
    CREATE TABLE analysis_reports (key TEXT PRIMARY KEY,report_kind TEXT,market_date TEXT,category_key TEXT,generated_at TEXT,generator_version TEXT,content_sha256 TEXT,content_json TEXT,imported_at TEXT);
    INSERT INTO category_capture_receipts VALUES ('2026-09-09','sump_pumps','${'a'.repeat(64)}');`);
  const db = { prepare(sql) { let args=[]; return {
    bind(...values) { args=values; return this; },
    async run() { return { meta: { changes: sqlite.prepare(sql).run(...args).changes } }; },
    async first() { return sqlite.prepare(sql).get(...args) ?? null; },
  }; } };
  return { sqlite, db };
}
const report = () => ({key:'daily/2026-09-09/sump_pumps.json',reportKind:'daily',marketDate:'2026-09-09',categoryKey:'sump_pumps',generatedAt:'2026-09-10T01:00:00Z',generatorVersion:'test',contentSha256:'b'.repeat(64)});

test('category report authorization is tied to that category receipt, not another market', async () => {
  const {sqlite,db}=environment();
  try {
    const wrong = {...report(), categoryKey:'pressure_washers',key:'daily/2026-09-09/pressure_washers.json'};
    assert.equal((await storeCategoryReport(db,'analysis_reports',wrong,'a'.repeat(64))).status,409);
    assert.equal(sqlite.prepare('SELECT count(*) n FROM analysis_reports').get().n,0);
    assert.equal((await storeCategoryReport(db,'analysis_reports',report(),'a'.repeat(64))).status,201);
  } finally {sqlite.close();}
});

test('same receipt cannot rewrite conclusions; a new verified category receipt can', async () => {
  const {sqlite,db}=environment();
  try {
    assert.equal((await storeCategoryReport(db,'analysis_reports',report(),'a'.repeat(64))).status,201);
    assert.equal((await storeCategoryReport(db,'analysis_reports',report(),'a'.repeat(64))).status,200);
    const changed={...report(),contentSha256:'c'.repeat(64)};
    assert.equal((await storeCategoryReport(db,'analysis_reports',changed,'a'.repeat(64))).status,409);
    sqlite.prepare('UPDATE category_capture_receipts SET receipt_sha256 = ?').run('d'.repeat(64));
    assert.equal((await storeCategoryReport(db,'analysis_reports',changed,'a'.repeat(64))).status,409);
    assert.equal((await storeCategoryReport(db,'analysis_reports',changed,'d'.repeat(64))).status,201);
  } finally {sqlite.close();}
});
