export type ProductType = "electric_pressure_washer" | "gas_pressure_washer" | "cordless_pressure_washer" | "surface_cleaner" | "pressure_washer_gun" | "hose" | "nozzle" | "foam_cannon" | "adapter_connector" | "extension_wand" | "sewer_jetter" | "chemical_cleaner" | "pump_protector" | "other_accessory" | "unknown";

export type ClassificationConfidence = "high" | "medium" | "low";

export type BrandSource = "verified_metadata" | "manual_review" | "unknown";

export type ProductMetadata = {
  marketplace: "AMAZON_US";
  asin: string;
  productType: ProductType;
  classificationConfidence: ClassificationConfidence;
  classificationRuleId: string | null;
  classificationRuleVersion: string;
  classificationEvidence: string[];
  rawBrand: string | null;
  normalizedBrand: string | null;
  normalizedBrandKey: string | null;
  brandAliasRuleId: string | null;
  brandSource: BrandSource;
  firstSeenMarketDate: string;
  lastSeenMarketDate: string;
};
