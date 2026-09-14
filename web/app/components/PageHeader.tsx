export function PageHeader({ eyebrow, title, description, children }: { eyebrow?: string; title: string; description: string; children?: React.ReactNode }) {
  return <div className="pageHeader"><div>{eyebrow && <div className="eyebrow">{eyebrow}</div>}<h1>{title}</h1><p>{description}</p></div>{children && <div className="headerTools">{children}</div>}</div>;
}
