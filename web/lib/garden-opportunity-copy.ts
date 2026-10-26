export const OPPORTUNITY_STATUS_LABELS = {
 observation: '观察线索',
 pending_verification: '待核验',
 worth_validating: '值得进一步验证',
 not_recommended: '暂不建议',
} as const;

export const OPPORTUNITY_STATUS_HELP = {
 observation: '保留观察的研究线索，尚未形成完整核验结论。',
 pending_verification: '尚未满足判断要求，请查看记录中的待核验项。',
 worth_validating: '已完成关键维度的人工核验，值得进一步验证，但不代表成交概率或销量预测。',
 not_recommended: '当前证据不支持继续推进，保留记录供后续复查。',
} as const;

export const OPPORTUNITY_DIMENSION_LABELS: Record<string, string> = {
 demand: '需求',
 competition: '竞争',
 differentiation: '差异化',
 risk: '销售可行性限制',
};

