export function QualityBadge({ children, tone = "info" }: { children: React.ReactNode; tone?: "good" | "warning" | "danger" | "info" }) {
  return <span className={`badge ${tone}`}>{children}</span>;
}
