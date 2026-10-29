export function ActionDock({ title = '下一步', children }: { title?: string; children: React.ReactNode }) {
  return <section className="actionDock workspacePanel" aria-label={title}><h2>{title}</h2><div>{children}</div></section>;
}
