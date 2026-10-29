export function TimelinePanel({ title = '时间线', children }: { title?: string; children: React.ReactNode }) {
  return <section className="timelinePanel workspacePanel" aria-label={title}><div className="panelHead"><h2>{title}</h2><span className="timelineMark">TIMELINE</span></div>{children}</section>;
}
