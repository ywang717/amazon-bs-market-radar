type BrandAliasRule = {
  id: string;
  canonicalName: string;
  aliases: readonly string[];
};

// Deployment copy generated from config/v2-brand-aliases.json. The PowerShell
// normalization layer remains authoritative; this copy lets the public write
// boundary independently reject payloads that do not follow those rules.
const brandAliasRules: readonly BrandAliasRule[] = [
  {
    id: "brand-westinghouse",
    canonicalName: "Westinghouse",
    aliases: ["Westinghouse", "WESTINGHOUSE", "Westinghouse Outdoor Power Equipment"],
  },
];

// Cross-runtime contract: raw and canonical brands are limited to printable
// ASCII U+0020-U+007E, and only consecutive ASCII spaces are folded.
const portableBrandText = /^[\x20-\x7e]+$/;

function normalizeBrandText(value: string) {
  const trimmedValue = value.replace(/^ +| +$/g, "");
  const portableValue = trimmedValue.toUpperCase() === "KÄRCHER" ? "KARCHER" : trimmedValue;
  if (!portableBrandText.test(portableValue)) {
    throw new Error("Brand text is outside the portable normalization boundary");
  }
  return portableValue.replace(/ +/g, " ");
}

const aliasByKey = new Map<string, BrandAliasRule>();
for (const rule of brandAliasRules) {
  if (normalizeBrandText(rule.canonicalName) !== rule.canonicalName) {
    throw new Error("Brand alias canonical name is not already normalized");
  }
  for (const alias of rule.aliases) {
    const key = normalizeBrandText(alias).toLowerCase();
    if (aliasByKey.has(key) && aliasByKey.get(key)?.id !== rule.id) {
      throw new Error("Brand alias catalog contains an ambiguous normalized alias");
    }
    aliasByKey.set(key, rule);
  }
}

export function normalizeTrustedBrand(rawBrand: string) {
  const raw = normalizeBrandText(rawBrand);
  const rule = aliasByKey.get(raw.toLowerCase());
  const normalizedBrand = rule?.canonicalName ?? raw;
  return {
    rawBrand: raw,
    normalizedBrand,
    normalizedBrandKey: normalizedBrand.toLowerCase(),
    brandAliasRuleId: rule?.id ?? null,
  };
}
