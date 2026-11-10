export function GET() {
  const body = [
    "# Amazon BS 市场雷达",
    "",
    "证据优先的 Amazon 美国站畅销榜市场情报看板。",
    "",
    "## 主要页面",
    "- /：今日市场判断与高优先级信号",
    "- /market：市场趋势与区间分析",
    "- /rankings：榜单排名与变化",
    "- /products：产品列表与历史趋势",
    "- /brands：品牌席位与产品结构",
    "- /reports：已验证报告归档",
    "- /analysis：实时解读、卖家情报和历史归档",
    "- /garden/opportunities：Garden 商机候选与人工核验",
    "- /methodology：指标定义、数据门槛和限制",
    "- /insights：数据更新时间、完整市场日和字段覆盖率",
    "",
    "## 数据口径",
    "排名、价格、评分和评论数均来自已验证的 Amazon 美国站公开榜单快照。缺失值保持为空，不代表销量、利润或成交概率。",
    "排名变化只描述快照差异；Garden 自动候选只是研究线索，人工核验发布后才形成状态结论。",
    "",
    "## 详细说明",
    "完整的 AI 阅读说明见 /llms-full.txt；方法与证据限制见 /methodology。",
    "",
  ].join("\n");
  return new Response(body, {
    headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "public, max-age=3600" },
  });
}
