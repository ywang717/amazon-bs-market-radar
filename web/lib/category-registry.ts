import { generatedCategoryRegistry } from "./generated/category-registry.ts";

export type RegistryPage = "overview" | "market" | "products" | "brands" | "rankings" | "reports" | "alerts" | "data_status" | "product_detail";
export type RuntimeRegistrySegment = { key: string; labelZh: string; productTypes: readonly string[] };
export type RuntimeRegistryCategory = {
  categoryKey: string;
  slug: string;
  labelZh: string;
  labelEn: string;
  nodeId: string;
  sourceUrl: string;
  targetCount: number;
  enabled: boolean;
  reportFileToken: string;
  segments: readonly RuntimeRegistrySegment[];
  defaults: Readonly<Record<RegistryPage, string>>;
};
export type RuntimeCategoryRegistry = {
  schemaVersion: "category-registry-v1";
  marketplace: { contextCode: "US"; storageCode: "AMAZON_US" };
  categories: readonly RuntimeRegistryCategory[];
  productTypeAttributes: Readonly<Record<string, readonly string[]>>;
};

const registryPages: readonly RegistryPage[] = [
  "overview",
  "market",
  "products",
  "brands",
  "rankings",
  "reports",
  "alerts",
  "data_status",
  "product_detail",
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requireRecord(value: unknown, description: string): Record<string, unknown> {
  if (!isRecord(value)) {
    throw new TypeError(`${description} must be an object.`);
  }
  return value;
}

function requireString(value: unknown, description: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`${description} must be a non-empty string.`);
  }
  return value;
}

function requireStringArray(value: unknown, description: string): readonly string[] {
  if (!Array.isArray(value) || value.some((entry) => typeof entry !== "string")) {
    throw new TypeError(`${description} must be a string array.`);
  }
  return value;
}

export function parseCategoryRegistry(input: unknown): RuntimeCategoryRegistry {
  const registry = requireRecord(input, "Category Registry");
  if (registry.schemaVersion !== "category-registry-v1") {
    throw new TypeError("Category Registry has an unsupported schema version.");
  }

  const marketplace = requireRecord(registry.marketplace, "Category Registry marketplace");
  if (marketplace.contextCode !== "US" || marketplace.storageCode !== "AMAZON_US") {
    throw new TypeError("Category Registry has an unsupported marketplace.");
  }
  if (!Array.isArray(registry.categories) || registry.categories.length === 0) {
    throw new TypeError("Category Registry categories must be a non-empty array.");
  }

  const categoryKeys = new Set<string>();
  const nodeIds = new Set<string>();
  for (const entry of registry.categories) {
    const category = requireRecord(entry, "Category Registry category");
    const categoryKey = requireString(category.categoryKey, "Category key");
    const nodeId = requireString(category.nodeId, `Category '${categoryKey}' node`);
    if (categoryKeys.has(categoryKey)) {
      throw new TypeError(`Category Registry contains duplicate category key: ${categoryKey}`);
    }
    if (nodeIds.has(nodeId)) {
      throw new TypeError(`Category Registry contains duplicate node: ${nodeId}`);
    }
    categoryKeys.add(categoryKey);
    nodeIds.add(nodeId);

    requireString(category.slug, `Category '${categoryKey}' slug`);
    requireString(category.labelZh, `Category '${categoryKey}' Chinese label`);
    requireString(category.labelEn, `Category '${categoryKey}' English label`);
    requireString(category.sourceUrl, `Category '${categoryKey}' source URL`);
    requireString(category.reportFileToken, `Category '${categoryKey}' report file token`);
    if (!Number.isInteger(category.targetCount) || (category.targetCount as number) < 1) {
      throw new TypeError(`Category '${categoryKey}' target count must be a positive integer.`);
    }
    if (typeof category.enabled !== "boolean") {
      throw new TypeError(`Category '${categoryKey}' enabled must be a boolean.`);
    }
    if (!Array.isArray(category.segments) || category.segments.length === 0) {
      throw new TypeError(`Category '${categoryKey}' segments must be a non-empty array.`);
    }
    const segmentKeys = new Set<string>();
    for (const entrySegment of category.segments) {
      const segment = requireRecord(entrySegment, `Category '${categoryKey}' segment`);
      const segmentKey = requireString(segment.key, `Category '${categoryKey}' segment key`);
      if (segmentKeys.has(segmentKey)) {
        throw new TypeError(`Category '${categoryKey}' contains duplicate segment key: ${segmentKey}`);
      }
      segmentKeys.add(segmentKey);
      requireString(segment.labelZh, `Category '${categoryKey}' segment '${segmentKey}' label`);
      requireStringArray(segment.productTypes, `Category '${categoryKey}' segment '${segmentKey}' Product Types`);
    }
    const defaults = requireRecord(category.defaults, `Category '${categoryKey}' defaults`);
    for (const page of registryPages) {
      const defaultSegment = requireString(defaults[page], `Category '${categoryKey}' default for '${page}'`);
      if (!segmentKeys.has(defaultSegment)) {
        throw new TypeError(`Category '${categoryKey}' has invalid default segment '${defaultSegment}' for '${page}'.`);
      }
    }
  }

  const productTypeAttributes = requireRecord(registry.productTypeAttributes, "Category Registry Product Type attributes");
  for (const [productType, labels] of Object.entries(productTypeAttributes)) {
    requireString(productType, "Product Type");
    requireStringArray(labels, `Product Type '${productType}' attributes`);
  }

  return input as RuntimeCategoryRegistry;
}

export const productionCategoryRegistry = parseCategoryRegistry(generatedCategoryRegistry);
