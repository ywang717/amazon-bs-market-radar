import assert from "node:assert/strict";
import { appendFileSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import test from "node:test";

import { parseCategoryRegistry, productionCategoryRegistry } from "../lib/category-registry.ts";
import { categories } from "../lib/catalog.ts";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const generatorPath = join(projectRoot, "scripts", "build-category-registry.mjs");
const registryPath = join(projectRoot, "config", "category-registry.json");

function runGenerator(args) {
  return spawnSync(process.execPath, [generatorPath, ...args], {
    cwd: projectRoot,
    encoding: "utf8",
  });
}

test("generated production registry preserves category nodes", () => {
  assert.deepEqual(
    Object.fromEntries(productionCategoryRegistry.categories.map((row) => [row.categoryKey, row.nodeId])),
    {
      pressure_washers: "552856",
      sump_pumps: "680335011",
      pressure_washer_accessories: "3023451",
    },
  );
});

test("Web catalog projects every enabled Category from the generated Registry", () => {
  assert.deepEqual(categories.map(({ key, label, nodeId, segments }) => ({ key, label, nodeId, segments })),
    productionCategoryRegistry.categories.filter(({ enabled }) => enabled).map((category) => ({
      key: category.categoryKey,
      label: category.labelZh,
      nodeId: category.nodeId,
      segments: category.segments.map(({ key }) => key),
    })));
});

test("runtime parser rejects duplicate nodes", () => {
  const fixture = structuredClone(productionCategoryRegistry);
  fixture.categories[1].nodeId = fixture.categories[0].nodeId;
  assert.throws(() => parseCategoryRegistry(fixture), /duplicate.*node/i);
});

test("check mode identifies a stale generated output without rewriting it", (t) => {
  const fixtureRoot = mkdtempSync(join(tmpdir(), "category-registry-check-"));
  t.after(() => rmSync(fixtureRoot, { recursive: true, force: true }));
  const sourcesOutput = join(fixtureRoot, "best-sellers-sources.json");
  const webOutput = join(fixtureRoot, "category-registry.ts");
  const outputArgs = [
    "--registry", registryPath,
    "--sources-output", sourcesOutput,
    "--web-output", webOutput,
  ];

  const generated = runGenerator(outputArgs);
  assert.equal(generated.status, 0, generated.stderr || generated.stdout);
  appendFileSync(webOutput, "// stale\n", "utf8");
  const staleBytes = readFileSync(webOutput);

  const checked = runGenerator(["--check", ...outputArgs]);
  assert.notEqual(checked.status, 0);
  assert.match(`${checked.stdout}\n${checked.stderr}`, /stale.*category-registry\.ts/i);
  assert.deepEqual(readFileSync(webOutput), staleBytes);
});

test("generation rejects conflicting Product Type attribute definitions", (t) => {
  const fixtureRoot = mkdtempSync(join(tmpdir(), "category-registry-conflict-"));
  t.after(() => rmSync(fixtureRoot, { recursive: true, force: true }));
  const fixtureConfig = join(fixtureRoot, "config");
  mkdirSync(fixtureConfig, { recursive: true });

  const registry = JSON.parse(readFileSync(registryPath, "utf8"));
  const attributes = JSON.parse(readFileSync(join(projectRoot, "config", "v2-product-attributes.json"), "utf8"));
  registry.categories[0].attribute_schema_path = "config/attributes-a.json";
  registry.categories[1].attribute_schema_path = "config/attributes-b.json";
  registry.categories[2].attribute_schema_path = "config/attributes-a.json";
  const conflictingAttributes = structuredClone(attributes);
  conflictingAttributes.product_types.unknown = ["冲突标签"];

  const fixtureRegistry = join(fixtureConfig, "category-registry.json");
  writeFileSync(fixtureRegistry, JSON.stringify(registry), "utf8");
  writeFileSync(join(fixtureConfig, "attributes-a.json"), JSON.stringify(attributes), "utf8");
  writeFileSync(join(fixtureConfig, "attributes-b.json"), JSON.stringify(conflictingAttributes), "utf8");

  const generated = runGenerator([
    "--registry", fixtureRegistry,
    "--sources-output", join(fixtureRoot, "sources.json"),
    "--web-output", join(fixtureRoot, "registry.ts"),
  ]);
  assert.notEqual(generated.status, 0);
  assert.match(`${generated.stdout}\n${generated.stderr}`, /Product Type.*unknown.*differently/i);
});

test("collector page-loading policy comes only from the canonical Registry", (t) => {
  const fixtureRoot = mkdtempSync(join(tmpdir(), "category-registry-policy-"));
  t.after(() => rmSync(fixtureRoot, { recursive: true, force: true }));
  const fixtureConfig = join(fixtureRoot, "config");
  mkdirSync(fixtureConfig, { recursive: true });

  const registry = JSON.parse(readFileSync(registryPath, "utf8"));
  const attributes = readFileSync(join(projectRoot, "config", "v2-product-attributes.json"), "utf8");
  registry.page_loading = {
    top_30_rule: "fixture_verified_rank_policy",
    pagination_rule: "Fixture pagination policy.",
  };
  const fixtureRegistry = join(fixtureConfig, "category-registry.json");
  const sourcesOutput = join(fixtureRoot, "sources.json");
  writeFileSync(fixtureRegistry, JSON.stringify(registry), "utf8");
  writeFileSync(join(fixtureConfig, "v2-product-attributes.json"), attributes, "utf8");

  const generated = runGenerator([
    "--registry", fixtureRegistry,
    "--sources-output", sourcesOutput,
    "--web-output", join(fixtureRoot, "registry.ts"),
  ]);
  assert.equal(generated.status, 0, generated.stderr || generated.stdout);
  assert.deepEqual(JSON.parse(readFileSync(sourcesOutput, "utf8")).page_loading, registry.page_loading);

  const generatorSource = readFileSync(generatorPath, "utf8");
  assert.doesNotMatch(generatorSource, /collect_only_verified_global_ranks_1_through_30/);
  assert.doesNotMatch(generatorSource, /A later page may be inspected only to verify its global ranks/);
});
