import type { CategoryKey } from "./catalog.ts";
import { productionCategoryRegistry } from "./category-registry.ts";
import type { ProductType } from "./product-metadata.ts";

export type ProductSpecification = {
  label: string;
  value: string;
};

function readLengthForObject(normalizedTitle: string, object: "HOSE" | "CORD") {
  const afterObject = normalizedTitle.match(new RegExp(`(\\d{1,3})\\s*(?:FT|FEET)\\b\\s+${object}\\b`));
  if (afterObject) return `${afterObject[1]} FT`;

  const beforeObject = normalizedTitle.match(new RegExp(`\\b${object}\\b\\s+(\\d{1,3})\\s*(?:FT|FEET)\\b`));
  if (beforeObject) return `${beforeObject[1]} FT`;

  return null;
}

function readAllExplicitSpecifications(title: string): ProductSpecification[] {
  const specs: ProductSpecification[] = [];
  const normalizedTitle = title.toUpperCase();
  const psi = normalizedTitle.match(/(\d{3,4})\s*PSI\b/);
  const gpm = normalizedTitle.match(/(\d(?:\.\d+)?)\s*GPM\b/);
  const horsepower = normalizedTitle.match(/(\d(?:\.\d+)?)\s*HP\b/);
  const voltage = normalizedTitle.match(/(\d{2,3})\s*V(?:OLT)?\b/);
  const hoseLength = readLengthForObject(normalizedTitle, "HOSE");
  const cordLength = readLengthForObject(normalizedTitle, "CORD");
  const nozzle = normalizedTitle.match(/(\d{1,3})\s*(?:DEGREE|°)\b/);
  const fittingSize = normalizedTitle.match(/(\d(?:\.\d+)?)\s*(?:IN|")\b/);

  if (psi) specs.push({ label: "工作压力", value: `${psi[1]} PSI` });
  if (gpm) specs.push({ label: "流量", value: `${gpm[1]} GPM` });
  if (/\bELECTRIC(?:-POWERED)?\b/.test(normalizedTitle)) specs.push({ label: "动力类型", value: "电动" });
  if (/\b(?:GAS|GAS-POWERED|GASOLINE)\b/.test(normalizedTitle)) specs.push({ label: "动力类型", value: "燃油" });
  if (horsepower) specs.push({ label: "马力", value: `${horsepower[1]} HP` });
  if (voltage) specs.push({ label: "电压", value: `${voltage[1]} V` });
  if (hoseLength) specs.push({ label: "软管长度", value: hoseLength });
  if (cordLength) specs.push({ label: "电源线长度", value: cordLength });
  if (nozzle) specs.push({ label: "喷嘴角度", value: `${nozzle[1]}°` });
  if (fittingSize) specs.push({ label: "接口尺寸", value: `${fittingSize[1]} in` });

  return specs.filter((spec, index, list) => list.findIndex((item) => item.label === spec.label && item.value === spec.value) === index);
}

const specificationLabelsByProductType = new Map(
  Object.entries(productionCategoryRegistry.productTypeAttributes).map(([productType, labels]) => [productType, new Set(labels)]),
);
const categorySpecificationLabels = new Map(productionCategoryRegistry.categories.map((category) => [
  category.categoryKey,
  new Set(category.segments.flatMap(({ productTypes }) => productTypes.flatMap((productType) =>
    [...(specificationLabelsByProductType.get(productType) ?? [])],
  ))),
]));

export function readExplicitSpecifications(title: string): ProductSpecification[] {
  return readAllExplicitSpecifications(title);
}

export function readExplicitSpecificationsForCategory(categoryKey: CategoryKey, title: string): ProductSpecification[] {
  const categoryLabels = categorySpecificationLabels.get(categoryKey) ?? new Set<string>();
  return readAllExplicitSpecifications(title).filter((spec) => categoryLabels.has(spec.label));
}

export function readExplicitSpecificationsForProduct(categoryKey: CategoryKey, productType: ProductType, title: string): ProductSpecification[] {
  const categoryLabels = categorySpecificationLabels.get(categoryKey) ?? new Set<string>();
  const productTypeLabels = specificationLabelsByProductType.get(productType) ?? new Set<string>();
  return readAllExplicitSpecifications(title).filter((spec) => categoryLabels.has(spec.label) && productTypeLabels.has(spec.label));
}
