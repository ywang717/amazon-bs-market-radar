import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";

const drizzleDirectory = fileURLToPath(new URL("../drizzle/", import.meta.url));
const postgresMigrationDirectory = fileURLToPath(new URL("../../db/migrations/", import.meta.url));

test("extends the PostgreSQL product type constraint without rewriting historical migrations", () => {
  const migration = readFileSync(`${postgresMigrationDirectory}015_best_sellers_product_type_v4.sql`, "utf8");
  for (const productType of ["foam_cannon", "adapter_connector", "extension_wand", "sewer_jetter"]) {
    assert.match(migration, new RegExp(`'${productType}'`));
  }
  assert.match(migration, /DROP CONSTRAINT IF EXISTS best_sellers_product_metadata_product_type_check/i);
  assert.match(migration, /ADD CONSTRAINT best_sellers_product_metadata_product_type_check/i);
});

test("registers every SQL migration with a generated snapshot, including product metadata", () => {
  const journal = JSON.parse(readFileSync(`${drizzleDirectory}meta/_journal.json`, "utf8"));
  const sqlTags = readdirSync(drizzleDirectory)
    .filter((file) => /^\d{4}_.+\.sql$/.test(file))
    .map((file) => file.replace(/\.sql$/, ""));
  const journalTags = journal.entries.map((entry) => entry.tag);

  assert.deepEqual(journalTags, sqlTags);
  assert.equal(existsSync(`${drizzleDirectory}meta/0002_snapshot.json`), true);
  const snapshot = JSON.parse(readFileSync(`${drizzleDirectory}meta/0002_snapshot.json`, "utf8"));
  assert.ok(snapshot.tables.seller_intelligence_reports);
  assert.ok(snapshot.tables.seller_intelligence_reports.indexes.idx_seller_intelligence_reports_market_date);
  assert.equal(existsSync(`${drizzleDirectory}meta/0003_snapshot.json`), true);
  const productMetadataSnapshot = JSON.parse(readFileSync(`${drizzleDirectory}meta/0003_snapshot.json`, "utf8"));
  assert.ok(productMetadataSnapshot.tables.product_metadata);
  assert.ok(productMetadataSnapshot.tables.product_metadata.indexes.idx_product_metadata_type);
  assert.ok(productMetadataSnapshot.tables.product_metadata.indexes.idx_product_metadata_brand);
  assert.equal(existsSync(`${drizzleDirectory}meta/0004_snapshot.json`), true);
  const conflictGuardSnapshot = JSON.parse(readFileSync(`${drizzleDirectory}meta/0004_snapshot.json`, "utf8"));
  assert.ok(conflictGuardSnapshot.tables.product_metadata_brand_conflict_guard);
});

test("applies the seller intelligence migration twice over a runtime-created legacy schema", () => {
  const database = new DatabaseSync(":memory:");
  database.exec("CREATE TABLE analysis_reports (key TEXT PRIMARY KEY NOT NULL, report_kind TEXT NOT NULL, market_date TEXT NOT NULL, category_key TEXT, generated_at TEXT NOT NULL, generator_version TEXT NOT NULL, content_sha256 TEXT NOT NULL, content_json TEXT NOT NULL, imported_at TEXT NOT NULL)");
  database.exec("CREATE INDEX idx_analysis_reports_market_date ON analysis_reports (market_date DESC, report_kind, category_key)");
  database.exec("CREATE TABLE seller_intelligence_reports (key TEXT PRIMARY KEY NOT NULL, report_kind TEXT NOT NULL, profile TEXT NOT NULL, market_date TEXT NOT NULL, category_key TEXT, generated_at TEXT NOT NULL, generator_version TEXT NOT NULL, content_sha256 TEXT NOT NULL, content_json TEXT NOT NULL, imported_at TEXT NOT NULL)");
  database.exec("CREATE INDEX idx_seller_intelligence_reports_market_date ON seller_intelligence_reports (market_date DESC, report_kind, profile, category_key)");
  const migration = readFileSync(`${drizzleDirectory}0002_seller_intelligence.sql`, "utf8");
  const statements = migration.split("--> statement-breakpoint").map((statement) => statement.trim()).filter(Boolean);

  for (const statement of statements) database.exec(statement);
  for (const statement of statements) database.exec(statement);

  assert.ok(database.prepare("SELECT name FROM sqlite_schema WHERE name = ?").get("analysis_reports"));
  assert.ok(database.prepare("SELECT name FROM sqlite_schema WHERE name = ?").get("seller_intelligence_reports"));
  const analysisIndex = database.prepare("SELECT sql FROM sqlite_schema WHERE type = 'index' AND name = ?").get("idx_analysis_reports_market_date");
  const sellerIndex = database.prepare("SELECT sql FROM sqlite_schema WHERE type = 'index' AND name = ?").get("idx_seller_intelligence_reports_market_date");
  assert.match(analysisIndex.sql, /market_date DESC, report_kind, category_key/i);
  assert.match(sellerIndex.sql, /market_date DESC, report_kind, profile, category_key/i);
  database.close();
});

test("applies the product metadata migration twice over the current schema", () => {
  const database = new DatabaseSync(":memory:");
  database.exec("CREATE TABLE observations (market_date TEXT NOT NULL, category_key TEXT NOT NULL, rank INTEGER NOT NULL, asin TEXT NOT NULL, title TEXT NOT NULL, url TEXT NOT NULL, price REAL, rating REAL, reviews INTEGER, PRIMARY KEY (market_date, category_key, rank))");
  const migration = readFileSync(`${drizzleDirectory}0003_product_metadata.sql`, "utf8");
  const statements = migration.split("--> statement-breakpoint").map((value) => value.trim()).filter(Boolean);
  for (const statement of statements) database.exec(statement);
  for (const statement of statements) database.exec(statement);
  const table = database.prepare("SELECT name FROM sqlite_schema WHERE type='table' AND name='product_metadata'").get();
  assert.equal(table.name, "product_metadata");
  database.close();
});

test("applies the dedicated product metadata conflict guard migration twice over an existing deployment", () => {
  const database = new DatabaseSync(":memory:");
  database.exec("CREATE TABLE product_metadata (marketplace TEXT NOT NULL, asin TEXT NOT NULL, product_type TEXT NOT NULL, classification_confidence TEXT NOT NULL, classification_rule_id TEXT, classification_rule_version TEXT NOT NULL, classification_evidence_json TEXT NOT NULL, raw_brand TEXT, normalized_brand TEXT, normalized_brand_key TEXT, brand_alias_rule_id TEXT, brand_source TEXT NOT NULL, first_seen_market_date TEXT NOT NULL, last_seen_market_date TEXT NOT NULL, PRIMARY KEY (marketplace, asin))");
  const migration = readFileSync(`${drizzleDirectory}0004_product_metadata_brand_conflict_guard.sql`, "utf8");
  const statements = migration.split("--> statement-breakpoint").map((value) => value.trim()).filter(Boolean);

  for (const statement of statements) database.exec(statement);
  for (const statement of statements) database.exec(statement);

  const guard = database.prepare("SELECT sql FROM sqlite_schema WHERE type='table' AND name='product_metadata_brand_conflict_guard'").get();
  assert.match(guard.sql, /product_metadata_brand_conflict_guard_check/);
  database.close();
});
