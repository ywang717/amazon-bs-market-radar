import type { MarketSignal } from "@/lib/ui-intelligence";
import { compactProductTitle, formatCompactNumber, formatExactNumber, formatPrice, formatReviewChange } from "@/lib/ui-intelligence";
import { RankDelta, RankDisplay } from "./RankDisplay";
import { serializeMarketContext, type MarketContext } from "@/lib/market-context";

const signalLabels = {
  rank_surge: "排名上升",
  rank_drop: "排名下降",
  top10_entry: "进入 Top10",
  top10_exit: "退出 Top10",
  first_seen: "首次发现",
  new_entry: "新入榜",
  re_entry: "重新入榜",
  exit: "退出 Top30",
  price_change: "价格变化",
  coupon_added: "新增优惠",
  coupon_removed: "优惠结束",
  review_momentum: "评论增长",
  review_anomaly: "评论数据异常波动",
  brand_expansion: "品牌席位扩张",
  brand_contraction: "品牌席位收缩",
};

const kindLabels = {
  rank_surge: "排名上升",
  rank_drop: "排名下降",
  top10_entry: "进入 Top10",
  top10_exit: "退出 Top10",
  first_seen: "首次发现",
  new_entry: "新入榜",
  re_entry: "重新入榜",
  exit: "退出 Top30",
  price_change: "价格变化",
  coupon_added: "新增优惠",
  coupon_removed: "优惠结束",
  review_momentum: "评论增长",
  review_anomaly: "评论数据异常波动",
  brand_expansion: "品牌席位扩张",
  brand_contraction: "品牌席位收缩",
};

function signalValue(signal: MarketSignal, value: string | number | null | undefined) {
  if (value === null || value === undefined) return "—";
  if (signal.kind === "price_change" && typeof value === "number") return formatPrice(value);
  if ((signal.kind === "review_momentum" || signal.kind === "review_anomaly") && typeof value === "number") return formatExactNumber(value);
  if ((signal.kind === "brand_expansion" || signal.kind === "brand_contraction") && typeof value === "number") return `${value} 席`;
  return String(value);
}

export function SignalCard({ signal, context, marketDate, featured = false }: { signal: MarketSignal; context: MarketContext; marketDate: string; featured?: boolean }) {
  const badge = signal.level === "high" ? "高优先级" : signal.level === "watch" ? "观察" : "动态";
  const brandSeatSignal = signal.kind === "brand_expansion" || signal.kind === "brand_contraction";
  const brandSeatExplanation = signal.delta === null ? "品牌席位无变化" : `较上一有效市场日${signal.delta > 0 ? "增加" : "减少"} ${Math.abs(signal.delta)} 个席位`;
  const reviewChange = (signal.kind === "review_momentum" || signal.kind === "review_anomaly") && typeof signal.previousValue === "number" && typeof signal.currentValue === "number"
    ? formatReviewChange(signal.previousValue, signal.currentValue)
    : null;
  return <article className={`signalCard ${signal.level} ${featured ? "featured" : ""}`}>
    <div className="signalAccent" aria-hidden="true" />
    <div className="signalHeader"><span className={`signalBadge ${signal.level}`}>{badge}</span><span>{signal.categoryLabel}</span></div>
    <h3 title={signal.title}>{compactProductTitle(signal.title, featured ? 72 : 48)}</h3><p className="signalSummary">{signalLabels[signal.kind]}</p>
    {(signal.previousRank !== null || signal.currentRank !== null) && <div className="signalRanks">{signal.previousRank !== null && <strong>#{signal.previousRank}</strong>}<span aria-hidden="true">→</span><RankDisplay rank={signal.currentRank} delta={signal.delta} /></div>}
    {signal.previousValue !== undefined && signal.currentValue !== undefined && <p className="signalValueChange">{reviewChange ? <b>{reviewChange}</b> : <><b>{signalValue(signal, signal.previousValue)}</b> → <b>{signalValue(signal, signal.currentValue)}</b>{signal.magnitude !== null && signal.magnitude !== undefined ? ` · 变化幅度 ${signal.magnitude}${signal.kind === "price_change" ? "%" : ""}` : ""}</>}</p>}
    <div className="signalFacts">
      {signal.delta !== null && <span>变化 {brandSeatSignal
        ? <span className={`rankDelta ${signal.delta > 0 ? "up" : signal.delta < 0 ? "down" : "neutral"}`} aria-label={brandSeatExplanation} title={brandSeatExplanation}><span aria-hidden="true">{signal.delta > 0 ? "↑" : signal.delta < 0 ? "↓" : "—"}</span>{signal.delta === 0 ? null : `${Math.abs(signal.delta)} 席`}</span>
        : <RankDelta delta={signal.delta} />}</span>}
      <span>价格 <b>{formatPrice(signal.price)}</b></span>
      <span>评论数 <b>{formatCompactNumber(signal.reviews)}</b></span>
    </div>
    <details className="signalEvidence"><summary>验证依据与人工核查</summary><p>{signal.previousValue !== undefined ? (reviewChange ?? `${signalValue(signal, signal.previousValue)} → ${signalValue(signal, signal.currentValue)}`) : "基于当前日与上一有效市场日的已验证变化。"}</p><p>{signal.kind === "review_anomaly" ? "Amazon 评论展示口径可能发生变化，本次异常不计入评论动量。" : "建议结合 Amazon 详情页人工确认。"}</p></details>
    <div className="signalFooter"><span>{kindLabels[signal.kind]} · 验证状态：已验证</span><a href={signal.asin ? `/products/${signal.asin}?${serializeMarketContext(context, { date: marketDate })}` : `/brands?${serializeMarketContext(context, { date: marketDate })}`} target="_top">{signal.asin ? "查看产品" : "查看品牌"} →</a></div>
  </article>;
}
