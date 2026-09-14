import type { ProductTimelineEventKind as TimelineEventKind } from "@/lib/ui-intelligence";

const eventLabels: Record<TimelineEventKind, string> = {
  price: "价格变化",
  coupon: "优惠变化",
  review: "评论变化",
  review_anomaly: "评论数据异常波动",
  first_seen: "首次发现",
  new_entry: "新入榜",
  exit: "退出 Top30",
  top10_entry: "进入 Top10",
  top10_exit: "退出 Top10",
  re_entry: "重新入榜",
};

export function TimelineEvent({ kind, date, detail }: { kind: TimelineEventKind; date: string; detail: string }) {
  return <li className={`timelineEvent ${kind}`}><span aria-hidden="true">{kind === "price" ? "$" : kind === "coupon" ? "%" : kind === "review" ? "✦" : kind === "review_anomaly" ? "!" : "↕"}</span><div><b>{eventLabels[kind]}</b><p>{detail}</p>{kind === "review_anomaly" && <p>Amazon 评论展示口径可能发生变化，本次异常不计入评论动量。</p>}</div><time>{date}</time></li>;
}
