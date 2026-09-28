export type SellerIntelligenceErrorCode = "database" | "no_data" | "report_generation" | "contract" | "threshold";

export type SellerIntelligencePublicError = {
  code: SellerIntelligenceErrorCode;
  message: string;
};

const messages: Record<SellerIntelligenceErrorCode, string> = {
  database: "数据服务暂时不可用，请稍后重试。",
  no_data: "当前范围暂无已验证数据。",
  report_generation: "卖家情报暂时无法生成，请稍后重试。",
  contract: "报告数据未通过验证，暂不展示。",
  threshold: "当前完整市场日不足，暂不输出稳定观察。",
};

export function classifySellerIntelligenceError(error: unknown): SellerIntelligencePublicError {
  const name = error instanceof Error ? error.name : "";
  const detail = error instanceof Error ? error.message : "";
  const code: SellerIntelligenceErrorCode = name === "EmptyDashboardStoreError"
    ? "no_data"
    : /竞争策略事实|卖家情报报告|合同|校验|验证/.test(detail)
      ? "contract"
      : /完整市场日不足|阈值/.test(detail)
        ? "threshold"
        : /sha256|生成|buildLiveSellerIntelligence/.test(detail)
          ? "report_generation"
          : "database";
  return { code, message: messages[code] };
}

export function publicSellerIntelligenceError(error: unknown) {
  return { error: classifySellerIntelligenceError(error) };
}
