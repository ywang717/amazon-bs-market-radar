import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const defaultProjectRoot = resolve(scriptDirectory, "..");

function parseArguments(argv) {
  const options = {
    check: false,
    registry: join(defaultProjectRoot, "config", "category-registry.json"),
    sourcesOutput: join(defaultProjectRoot, "config", "best-sellers-sources.json"),
    webOutput: join(defaultProjectRoot, "web", "lib", "generated", "category-registry.ts"),
  };
  const pathOptions = new Map([
    ["--registry", "registry"],
    ["--sources-output", "sourcesOutput"],
    ["--web-output", "webOutput"],
  ]);

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--check") {
      options.check = true;
      continue;
    }
    const option = pathOptions.get(argument);
    if (!option) {
      throw new Error(`Unknown argument: ${argument}`);
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for ${argument}`);
    }
    options[option] = resolve(process.cwd(), value);
    index += 1;
  }
  return options;
}

function readJson(path, description) {
  let source;
  try {
    source = readFileSync(path, "utf8");
  } catch (error) {
    throw new Error(`${description} does not exist: ${path}`, { cause: error });
  }
  try {
    return JSON.parse(source);
  } catch (error) {
    throw new Error(`${description} is not valid JSON: ${path}`, { cause: error });
  }
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requireRecord(value, description) {
  if (!isRecord(value)) {
    throw new Error(`${description} must be an object.`);
  }
  return value;
}

function requireArray(value, description) {
  if (!Array.isArray(value)) {
    throw new Error(`${description} must be an array.`);
  }
  return value;
}

function projectRootForRegistry(registryPath) {
  const registryDirectory = dirname(registryPath);
  return basename(registryDirectory).toLowerCase() === "config"
    ? dirname(registryDirectory)
    : registryDirectory;
}

function resolveReference(projectRoot, reference, description) {
  if (typeof reference !== "string" || reference.length === 0) {
    throw new Error(`${description} path is required.`);
  }
  const path = isAbsolute(reference) ? resolve(reference) : resolve(projectRoot, reference);
  const relative = path.slice(resolve(projectRoot).length);
  if (relative && !relative.startsWith("\\") && !relative.startsWith("/")) {
    throw new Error(`${description} escapes the project root: ${reference}`);
  }
  if (!existsSync(path)) {
    throw new Error(`${description} does not exist: ${reference}`);
  }
  return path;
}

function sameJsonValue(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function mergeProductTypeAttributes(registry, projectRoot) {
  const merged = {};
  for (const category of requireArray(registry.categories, "Category Registry categories")) {
    const row = requireRecord(category, "Category Registry category");
    const schemaPath = resolveReference(projectRoot, row.attribute_schema_path, "Category attribute schema");
    const schema = requireRecord(readJson(schemaPath, "Category attribute schema"), "Category attribute schema");
    if (schema.schema_version !== "product-attribute-schema-v1") {
      throw new Error(`Category attribute schema has an unsupported schema version: ${schemaPath}`);
    }
    const productTypes = requireRecord(schema.product_types, "Category attribute schema product_types");
    for (const [productType, labels] of Object.entries(productTypes)) {
      requireArray(labels, `Product Type '${productType}' attributes`);
      if (Object.hasOwn(merged, productType) && !sameJsonValue(merged[productType], labels)) {
        throw new Error(`Product Type '${productType}' is defined differently by referenced attribute schemas.`);
      }
      merged[productType] = labels;
    }
  }
  return merged;
}

function normalizeRegistry(registryPath) {
  const registry = requireRecord(readJson(registryPath, "Category Registry"), "Category Registry");
  if (registry.schema_version !== "category-registry-v1") {
    throw new Error("Unsupported Category Registry schema version.");
  }
  const marketplace = requireRecord(registry.marketplace, "Category Registry marketplace");
  const pageLoading = requireRecord(registry.page_loading, "Category Registry page_loading");
  const categories = requireArray(registry.categories, "Category Registry categories");
  const projectRoot = projectRootForRegistry(registryPath);
  const productTypeAttributes = mergeProductTypeAttributes(registry, projectRoot);

  const webCategories = categories.map((category) => {
    const row = requireRecord(category, "Category Registry category");
    return {
      categoryKey: row.category_key,
      slug: row.slug,
      labelZh: row.label_zh,
      labelEn: row.label_en,
      nodeId: row.amazon_node_id,
      sourceUrl: row.source_url,
      targetCount: row.target_count,
      enabled: row.enabled,
      reportFileToken: row.report_file_token,
      segments: requireArray(row.segments, `Category '${row.category_key}' segments`).map((segment) => {
        const segmentRow = requireRecord(segment, `Category '${row.category_key}' segment`);
        return {
          key: segmentRow.key,
          labelZh: segmentRow.label_zh,
          productTypes: segmentRow.product_types,
        };
      }),
      defaults: row.defaults,
    };
  });

  const targetCounts = new Set(webCategories.map((category) => category.targetCount));
  if (targetCounts.size !== 1) {
    throw new Error("Collector compatibility artifact requires one shared target count.");
  }

  return {
    sources: {
      marketplace: marketplace.storage_code,
      target_count: webCategories[0].targetCount,
      sources: webCategories.map((category) => ({
        category_key: category.categoryKey,
        category_slug: category.slug,
        amazon_node_id: category.nodeId,
        display_name: `${category.labelEn} Best Sellers`,
        url: category.sourceUrl,
        active: category.enabled,
      })),
      page_loading: pageLoading,
    },
    web: {
      schemaVersion: registry.schema_version,
      marketplace: {
        contextCode: marketplace.context_code,
        storageCode: marketplace.storage_code,
      },
      categories: webCategories,
      productTypeAttributes,
    },
  };
}

function sortObjectKeys(value) {
  if (Array.isArray(value)) {
    return value.map(sortObjectKeys);
  }
  if (!isRecord(value)) {
    return value;
  }
  return Object.fromEntries(
    Object.keys(value).sort().map((key) => [key, sortObjectKeys(value[key])]),
  );
}

function renderArtifacts(registryPath) {
  const normalized = normalizeRegistry(registryPath);
  const sources = `${JSON.stringify(sortObjectKeys(normalized.sources), null, 2)}\n`;
  const webRegistry = sortObjectKeys(normalized.web);
  const serializedRegistry = JSON.stringify(webRegistry, null, 2);
  const typeScript = `export const generatedCategoryRegistry = ${serializedRegistry} as const;\n\n`
    + `export type CategoryKey = (typeof generatedCategoryRegistry.categories)[number]["categoryKey"];\n`
    + `export type SegmentKey = (typeof generatedCategoryRegistry.categories)[number]["segments"][number]["key"];\n`;
  return { sources, typeScript };
}

function writeArtifact(path, content) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content, "utf8");
}

function assertCurrent(path, expected) {
  if (!existsSync(path) || !readFileSync(path).equals(Buffer.from(expected, "utf8"))) {
    throw new Error(`Stale generated output: ${path}`);
  }
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const artifacts = renderArtifacts(options.registry);
  if (options.check) {
    assertCurrent(options.sourcesOutput, artifacts.sources);
    assertCurrent(options.webOutput, artifacts.typeScript);
    return;
  }
  writeArtifact(options.sourcesOutput, artifacts.sources);
  writeArtifact(options.webOutput, artifacts.typeScript);
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
