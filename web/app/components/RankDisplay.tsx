export function RankDelta({ delta, comparisonLabel = "较上一有效市场日" }: { delta: number | null; comparisonLabel?: string }) {
  if (delta === null || delta === 0) return <span className="rankDelta neutral">—</span>;
  const improved = delta > 0;
  const explanation = `${comparisonLabel}${improved ? "上升" : "下降"} ${Math.abs(delta)} 名`;
  return <span className={`rankDelta ${improved ? "up" : "down"}`} aria-label={explanation} title={explanation}><span aria-hidden="true">{improved ? "↑" : "↓"}</span>{Math.abs(delta)}</span>;
}

export function RankDisplay({ rank, delta }: { rank: number | null; delta?: number | null }) {
  return <span className="rankDisplay"><strong>{rank === null ? "—" : `#${rank}`}</strong>{delta !== undefined && delta !== null && delta !== 0 ? <RankDelta delta={delta} /> : null}</span>;
}
