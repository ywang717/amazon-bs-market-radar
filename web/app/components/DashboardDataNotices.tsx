import { RetryPage } from "./RetryPage";
export function DashboardDataNotices({ source, metadataAvailable }: {
  source: "d1" | "seed_fallback";
  metadataAvailable: boolean;
}) {
  return <>
    <div className="dataQualityStatus" role="status"><span>数据质量</span><strong>{source === "d1" ? metadataAvailable ? "实时完整" : "实时部分可用" : "回退数据"}</strong><small>{source === "d1" ? metadataAvailable ? "排名与元数据均可用" : "排名可用，元数据字段缺失" : "实时读取失败，展示已验证回退快照"}</small></div>
    {source === "seed_fallback" && <p className="sourceNotice" role="status">实时数据暂不可用，当前展示已验证回退数据。</p>}
    {source === "seed_fallback" && <RetryPage/>}
    {source === "d1" && !metadataAvailable && <p className="sourceNotice" role="status">实时排名可用；产品品牌与类型元数据暂时缺失，相关字段显示为“未知”。</p>}
  </>;
}
