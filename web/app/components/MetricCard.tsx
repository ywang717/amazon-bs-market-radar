export function MetricCard({ value, label, detail, tone = "neutral" }: {
  value: string | number;
  label: string;
  detail?: string;
  tone?: "neutral" | "danger" | "warning" | "positive";
}) {
  return <article className={`metricCard ${tone}`}><strong>{value}</strong><h2>{label}</h2>{detail && <p>{detail}</p>}</article>;
}
