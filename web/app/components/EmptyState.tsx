import { ContextLink } from "./ContextLink";

export function EmptyState({ title = "暂无重大异常", description, href = "/market", linkLabel = "查看市场" }: {
  title?: string;
  description: string;
  href?: string;
  linkLabel?: string;
}) {
  return <div className="emptyState"><span aria-hidden="true">✓</span><div><h3>{title}</h3><p>{description}</p><ContextLink href={href} target="_top">{linkLabel} →</ContextLink></div></div>;
}
