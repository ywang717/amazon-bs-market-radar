import { productionCategoryRegistry } from "./category-registry.ts";
import type { CategoryKey, SegmentKey } from "./generated/category-registry.ts";

export type { CategoryKey, SegmentKey } from "./generated/category-registry.ts";

export type CatalogCategory = {
  key: CategoryKey;
  label: string;
  nodeId: string;
  short: string;
  segments: readonly SegmentKey[];
};

export const categories = productionCategoryRegistry.categories
  .filter(({ enabled }) => enabled)
  .map((category): CatalogCategory => ({
    key: category.categoryKey as CategoryKey,
    label: category.labelZh,
    nodeId: category.nodeId,
    short: category.labelZh,
    segments: category.segments.map(({ key }) => key as SegmentKey),
  }));

export const categoryByKey = Object.fromEntries(
  categories.map((category) => [category.key, category]),
) as Record<CategoryKey, CatalogCategory>;
