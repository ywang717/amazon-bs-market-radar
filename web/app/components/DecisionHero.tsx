export function DecisionHero({ title, summary, tone = 'neutral', className = '', children }: { title: string; summary: string; tone?: 'neutral' | 'positive' | 'warning' | 'danger'; className?: string; children?: React.ReactNode }) {
  return <section className={`decisionHero ${tone} ${className}`.trim()} aria-label="当前判断"><div><span className="decisionKicker">当前判断</span><h2>{title}</h2><p>{summary}</p></div>{children && <div className="decisionActions">{children}</div>}</section>;
}
