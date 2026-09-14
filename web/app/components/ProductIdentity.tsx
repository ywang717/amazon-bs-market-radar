import { productDisplayName } from "@/lib/ui-intelligence";
import type { ProductType } from "@/lib/product-metadata";

const typeLabels: Record<ProductType, string> = {
  electric_pressure_washer: "电动",
  gas_pressure_washer: "燃油",
  cordless_pressure_washer: "无线",
  surface_cleaner: "表面清洁器",
  pressure_washer_gun: "喷枪",
  hose: "软管",
  nozzle: "喷嘴",
  foam_cannon: "泡沫壶",
  adapter_connector: "转接头",
  extension_wand: "延长杆",
  sewer_jetter: "管道疏通喷管",
  chemical_cleaner: "清洁剂",
  pump_protector: "泵保护剂",
  other_accessory: "其他配件",
  unknown: "未知",
};

export function productTypeLabel(type: ProductType) {
  return typeLabels[type];
}

export function ProductTypeBadge({ type }: { type: ProductType }) {
  return <span className="productTypeBadge">{productTypeLabel(type)}</span>;
}

export function ProductIdentity({ asin, title, type = "unknown", brand, href }: {
  asin: string;
  title: string;
  type?: ProductType;
  brand?: string | null;
  href?: string;
}) {
  const compact = productDisplayName(title, brand ?? null);
  const identity = <div className="productIdentityText"><strong title={title}>{compact}</strong><span>{brand ? `${brand} · ` : ""}{asin} · <ProductTypeBadge type={type} /></span></div>;
  return <div className="productIdentity"><div className="productThumbnail" aria-hidden="true"><span>BS</span></div>{href ? <a href={href} target="_top">{identity}</a> : identity}</div>;
}
