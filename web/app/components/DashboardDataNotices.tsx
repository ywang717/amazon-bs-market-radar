export function DashboardDataNotices({ source, metadataAvailable }: {
  source: "d1" | "seed_fallback";
  metadataAvailable: boolean;
}) {
  return <>
    {source === "seed_fallback" && <p className="sourceNotice" role="status">实时数据暂不可用，当前展示已验证回退数据。</p>}
    {source === "d1" && !metadataAvailable && <p className="sourceNotice" role="status">实时排名可用；产品品牌与类型元数据暂时缺失，相关字段显示为“未知”。</p>}
  </>;
}
