import {
  productionCategoryRegistry,
  type RegistryPage,
  type RuntimeCategoryRegistry,
} from "./category-registry.ts";
import type { CategoryKey, SegmentKey } from "./generated/category-registry.ts";
import { type ProductMetadata, type ProductType } from "./product-metadata.ts";

export type MarketplaceCode = "US";
export type { CategoryKey, SegmentKey } from "./generated/category-registry.ts";
export type MarketContext = { marketplace: MarketplaceCode; category: CategoryKey; segment: SegmentKey };
export type MarketContextResult = { ok: true; context: MarketContext } | { ok: false; error: "unsupported_market_context" };
export type PageMarket = RegistryPage;

type RuntimeMarketContext = { marketplace: string; category: string; segment: string };
type RuntimeMarketContextResult = { ok: true; context: RuntimeMarketContext } | { ok: false; error: "unsupported_market_context" };
type SegmentDefinition = { key: string; label: string; productTypes?: readonly string[] };
type MarketDefinition = { categoryId: string; label: string; amazonNode: string; segments: readonly SegmentDefinition[] };

const pages: readonly PageMarket[] = [
  "overview", "market", "products", "brands", "rankings", "reports", "alerts", "data_status", "product_detail",
];
const canonicalSegment = (value: string | null | undefined) => value === "all_bestsellers" ? "all" : value;

function toSearchParams(input: URLSearchParams | Record<string, string | string[] | undefined>) {
  if (input instanceof URLSearchParams) return new URLSearchParams(input);
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(input)) {
    const first = Array.isArray(value) ? value[0] : value;
    if (first !== undefined) params.set(key, first);
  }
  return params;
}

export function createMarketContextResolver(registry: RuntimeCategoryRegistry) {
  const enabled = registry.categories.filter(({ enabled }) => enabled);
  if (!enabled.length) throw new TypeError("Category Registry must enable at least one category.");
  const categoryByKey = new Map(enabled.map((category) => [category.categoryKey, category]));
  const defaultCategory = enabled[0];
  const MARKET_CONFIG = Object.fromEntries(enabled.map((category) => [category.categoryKey, {
    categoryId: category.categoryKey,
    label: category.labelZh,
    amazonNode: category.nodeId,
    segments: category.segments.map((segment) => ({
      key: segment.key,
      label: segment.labelZh,
      ...(segment.productTypes.length ? { productTypes: segment.productTypes } : {}),
    })),
  }])) as Record<string, MarketDefinition>;
  const PAGE_MARKET_DEFAULTS = Object.fromEntries(pages.map((page) => [
    page,
    Object.fromEntries(enabled.map((category) => [category.categoryKey, category.defaults[page]])),
  ])) as Record<PageMarket, Record<string, string>>;

  const isSegmentSupported = (category: string, segment: string) => {
    const canonical = canonicalSegment(segment);
    return categoryByKey.get(category)?.segments.some(({ key }) => key === canonical) ?? false;
  };

  const resolveSegmentForCategory = (page: PageMarket, category: string, requested?: string | null) => {
    const canonical = canonicalSegment(requested);
    return canonical && isSegmentSupported(category, canonical)
      ? canonical
      : categoryByKey.get(category)?.defaults[page] ?? defaultCategory.defaults[page];
  };

  const validateMarketContext = (input: { marketplace: string; category: string; segment: string }): RuntimeMarketContextResult => {
    const category = categoryByKey.get(input.category);
    const segment = canonicalSegment(input.segment);
    const supported = Boolean(segment && category?.segments.some(({ key }) => key === segment));
    if (input.marketplace !== registry.marketplace.contextCode || !category || !supported) {
      return { ok: false, error: "unsupported_market_context" };
    }
    return { ok: true, context: { marketplace: registry.marketplace.contextCode, category: category.categoryKey, segment: segment! } };
  };

  const marketContextCacheKey = (context: RuntimeMarketContext, scope: { date?: string | null; window?: string | null } = {}) =>
    [context.marketplace, context.category, context.segment, scope.date || "latest", scope.window || "snapshot"].join(":");

  const serializeMarketContext = (context: RuntimeMarketContext, input: URLSearchParams | Record<string, string | string[] | undefined> = new URLSearchParams()) => {
    const params = toSearchParams(input);
    params.delete("marketplace");
    params.set("category", context.category);
    params.set("segment", context.segment);
    return params.toString();
  };

  const resolvePageMarketContext = (page: PageMarket, input: URLSearchParams | Record<string, string | string[] | undefined>) => {
    const original = toSearchParams(input);
    const rawCategory = original.get("category");
    const rawSegment = original.get("segment");
    const categoryIsValid = Boolean(rawCategory && categoryByKey.has(rawCategory));
    const category = categoryIsValid ? rawCategory! : defaultCategory.categoryKey;
    const segment = resolveSegmentForCategory(page, category, categoryIsValid ? rawSegment : null);
    const context = { marketplace: registry.marketplace.contextCode, category, segment };
    const normalized = new URLSearchParams(serializeMarketContext(context, original));
    const explicitCategoryIsInvalid = rawCategory !== null && !categoryIsValid;
    const explicitSegmentIsInvalid = rawSegment !== null
      && (!categoryIsValid || canonicalSegment(rawSegment) !== rawSegment || !isSegmentSupported(category, rawSegment));
    return {
      context,
      searchParams: normalized,
      needsNormalization: explicitCategoryIsInvalid || explicitSegmentIsInvalid || original.has("marketplace"),
    };
  };

  const marketContextLabels = (context: RuntimeMarketContext) => {
    const category = categoryByKey.get(context.category);
    return {
      category: category?.labelZh ?? "",
      segment: category?.segments.find(({ key }) => key === context.segment)?.labelZh ?? "",
    };
  };

  const productTypeFiltersForContext = (context: RuntimeMarketContext) => {
    const segments = MARKET_CONFIG[context.category]?.segments.filter(({ key, productTypes }) => key !== "all" && (productTypes?.length ?? 0) > 0) ?? [];
    return segments.filter((candidate) => !segments.some((other) =>
      other.key !== candidate.key
      && candidate.productTypes!.length > other.productTypes!.length
      && other.productTypes!.every((productType) => candidate.productTypes!.includes(productType)),
    ));
  };

  const filterAnalyticalMarket = <T extends { asin: string }>(
    rows: T[],
    metadata: Pick<ProductMetadata, "asin" | "productType">[],
    context: RuntimeMarketContext,
  ): T[] => {
    if (context.segment === "all") return rows.slice();
    const allowedTypes = categoryByKey.get(context.category)?.segments.find(({ key }) => key === context.segment)?.productTypes;
    if (!allowedTypes) return [];
    const allowed = new Set<string>(allowedTypes);
    const typeByAsin = new Map(metadata.map(({ asin, productType }) => [asin, productType]));
    return rows.filter((row) => {
      const productType = typeByAsin.get(row.asin);
      return productType !== undefined && allowed.has(productType);
    });
  };

  return {
    registry,
    enabled,
    categoryByKey,
    MARKET_CONFIG,
    PAGE_MARKET_DEFAULTS,
    isSegmentSupported,
    resolveSegmentForCategory,
    validateMarketContext,
    marketContextCacheKey,
    serializeMarketContext,
    resolvePageMarketContext,
    marketContextLabels,
    productTypeFiltersForContext,
    filterAnalyticalMarket,
  };
}

export type MarketContextResolver = ReturnType<typeof createMarketContextResolver>;
export const productionMarketContextResolver = createMarketContextResolver(productionCategoryRegistry);

export const MARKET_CONFIG = productionMarketContextResolver.MARKET_CONFIG as Record<CategoryKey, MarketDefinition>;
export const PAGE_MARKET_DEFAULTS = productionMarketContextResolver.PAGE_MARKET_DEFAULTS as Record<PageMarket, Record<CategoryKey, SegmentKey>>;

export function isMachineProductType(productType: ProductType) {
  return productionMarketContextResolver.enabled.some((category) =>
    category.segments.some((segment) => segment.key === "machines" && segment.productTypes.includes(productType)),
  );
}

export function isAccessoryProductType(productType: ProductType) {
  const machineTypes = new Set(productionMarketContextResolver.enabled.flatMap((category) =>
    category.segments.filter(({ key }) => key === "machines").flatMap(({ productTypes }) => productTypes),
  ));
  return productionMarketContextResolver.enabled.some((category) => category.segments.some(({ key, productTypes }) =>
    key !== "all" && key !== "machines" && productTypes.includes(productType) && !machineTypes.has(productType),
  ));
}

export function isSegmentSupported(category: CategoryKey, segment: string): segment is SegmentKey {
  return productionMarketContextResolver.isSegmentSupported(category, segment);
}

export function resolveSegmentForCategory(page: PageMarket, category: CategoryKey, requested?: string | null): SegmentKey {
  return productionMarketContextResolver.resolveSegmentForCategory(page, category, requested) as SegmentKey;
}

export function resolveMarketDate(requested: string | null | undefined, validDates: readonly string[]) {
  const ordered = [...validDates].filter((value) => /^\d{4}-\d{2}-\d{2}$/.test(value)).toSorted();
  const latest = ordered.at(-1) ?? null;
  if (!requested) return { marketDate: latest, needsNormalization: false };
  if (ordered.includes(requested)) return { marketDate: requested, needsNormalization: false };
  return { marketDate: latest, needsNormalization: true };
}

export function marketContextCacheKey(context: MarketContext, scope: { date?: string | null; window?: string | null } = {}) {
  return productionMarketContextResolver.marketContextCacheKey(context, scope);
}

export function validateMarketContext(input: { marketplace: string; category: string; segment: string }): MarketContextResult {
  return productionMarketContextResolver.validateMarketContext(input) as MarketContextResult;
}

export function resolvePublicMarketQuery(
  input: { marketplace?: string | null; category?: string | null; segment?: string | null; page?: PageMarket },
  resolver: MarketContextResolver = productionMarketContextResolver,
): RuntimeMarketContextResult {
  const page = input.page ?? "products";
  const category = input.category ?? resolver.enabled[0].categoryKey;
  const segment = input.segment ?? resolver.resolveSegmentForCategory(page, category);
  return resolver.validateMarketContext({ marketplace: input.marketplace ?? resolver.registry.marketplace.contextCode, category, segment });
}

export function parseMarketContext(url: URL): MarketContextResult {
  return resolvePublicMarketQuery({
    marketplace: url.searchParams.get("marketplace"),
    category: url.searchParams.get("category"),
    segment: url.searchParams.get("segment"),
  }, productionMarketContextResolver) as MarketContextResult;
}

export function serializeMarketContext(context: MarketContext, input: URLSearchParams | Record<string, string | string[] | undefined> = new URLSearchParams()) {
  return productionMarketContextResolver.serializeMarketContext(context, input);
}

export function resolvePageMarketContext(page: PageMarket, input: URLSearchParams | Record<string, string | string[] | undefined>) {
  return productionMarketContextResolver.resolvePageMarketContext(page, input) as {
    context: MarketContext;
    searchParams: URLSearchParams;
    needsNormalization: boolean;
  };
}

export function marketContextLabels(context: MarketContext) {
  return productionMarketContextResolver.marketContextLabels(context);
}

export function productTypeFiltersForContext(context: MarketContext) {
  return productionMarketContextResolver.productTypeFiltersForContext(context) as Array<{ key: SegmentKey; label: string; productTypes?: readonly ProductType[] }>;
}

export function pageMarketForPath(pathname: string): PageMarket {
  if (pathname.startsWith("/market")) return "market";
  if (pathname.startsWith("/products/")) return "product_detail";
  if (pathname.startsWith("/products")) return "products";
  if (pathname.startsWith("/brands")) return "brands";
  if (pathname.startsWith("/rankings")) return "rankings";
  if (pathname.startsWith("/reports")) return "reports";
  if (pathname.startsWith("/analysis")) return "alerts";
  if (pathname.startsWith("/insights")) return "data_status";
  return "overview";
}

export function filterAnalyticalMarket<T extends { asin: string }>(rows: T[], metadata: Pick<ProductMetadata, "asin" | "productType">[], context: MarketContext): T[] {
  return productionMarketContextResolver.filterAnalyticalMarket(rows, metadata, context);
}
