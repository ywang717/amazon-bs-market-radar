export function EvidenceRail({ title = '证据状态', items, children }: { title?: string; items?: Array<{ label: string; value: React.ReactNode; tone?: 'good' | 'warning' | 'danger' }>; children?: React.ReactNode }) {
  return <section className="evidenceRail workspacePanel" aria-label={title}><div className="panelHead"><h2>{title}</h2><span className="evidenceDot" /></div>{items && <dl>{items.map((item) => <div key={item.label}><dt>{item.label}</dt><dd className={item.tone ? `evidence-${item.tone}` : undefined}>{item.value}</dd></div>)}</dl>}{children}</section>;
}
