"use client";
import { useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { MARKET_DIMENSIONS, type GardenOpportunityRecord } from "@/lib/garden-opportunity";
import { appendEvidenceSource, editEvidenceSource, removeEvidenceSource, reviewInputIssues } from "@/lib/garden-review-editor";
import { validateGardenReview } from "@/lib/garden-review-contract";

const names={demand:'需求',competition:'竞争',differentiation:'差异化',risk:'销售可行性限制'};
const labels={observation:'观察线索',pending_verification:'待核验',worth_validating:'值得进一步验证',not_recommended:'暂不建议'};
const sourceKinds={invoice:'发票',settlement:'结算',order:'订单',quote:'引用/报价',official_fee:'官方说明',assumption:'假设',exchange_rate:'汇率'};
type Draft={status:GardenOpportunityRecord['status'];dimensions:GardenOpportunityRecord['dimensions'];confirmed:boolean;salesBlocked:boolean;rejectionBasis:'market'|'sales_barrier';reason:string};
const emptyDraft=():Draft=>({status:'pending_verification',dimensions:{},confirmed:false,salesBlocked:true,rejectionBasis:'market',reason:''});
type Result={message:string;status?:keyof typeof labels;issues?:string[];summaries?:{name:string;conclusion:string;sourceCount:number}[]};
function returnHref(value:string|null){try{if(!value?.startsWith('/')||value.startsWith('//'))return '/garden/opportunities';const url=new URL(value,'https://market-radar.local');return url.origin==='https://market-radar.local'&&['/garden','/garden/products','/garden/opportunities'].includes(url.pathname)?url.pathname+url.search:'/garden/opportunities';}catch{return '/garden/opportunities';}}
async function request(url:string,init:RequestInit={}) {
 const controller=new AbortController();const timeout=window.setTimeout(()=>controller.abort(),10000);
 try{const response=await fetch(url,{...init,signal:controller.signal});const value=await response.json();return {response,value};}finally{window.clearTimeout(timeout);}
}
export function ReviewEditor({categories}:{categories:{key:string;label:string}[]}) {
 const params=useSearchParams();const [asin,setAsin]=useState(params.get('asin')||'');const [categoryKey,setCategoryKey]=useState(params.get('categoryKey')||'');
 const [secret,setSecret]=useState('');const [revision,setRevision]=useState(0);const [published,setPublished]=useState(false);const [draft,setDraft]=useState<Draft>(emptyDraft);const [result,setResult]=useState<Result|null>(null);const [busy,setBusy]=useState(false);const [dirty,setDirty]=useState(false);const [legacy,setLegacy]=useState(false);const [conflict,setConflict]=useState(false);
 const scopeValid=/^B[A-Z0-9]{9}$/.test(asin)&&categories.some(c=>c.key===categoryKey);
 const issues=reviewInputIssues(draft);const cannotPublish=published&&issues.length>0;
 useEffect(()=>{if(!dirty)return;const warn=(event:BeforeUnloadEvent)=>{event.preventDefault();event.returnValue='';};window.addEventListener('beforeunload',warn);return()=>window.removeEventListener('beforeunload',warn);},[dirty]);
 function change(patch:Partial<Draft>){setDraft(previous=>({...previous,...patch,confirmed:false}));setDirty(true);}
 function resetScope(next:{asin?:string;categoryKey?:string}){if(dirty&&!window.confirm('切换核验对象将清除未保存内容，是否继续？'))return;if(next.asin!==undefined)setAsin(next.asin);if(next.categoryKey!==undefined)setCategoryKey(next.categoryKey);setRevision(0);setDraft(emptyDraft());setPublished(false);setResult(null);setDirty(false);setLegacy(false);setConflict(false);}
 async function load(protectedRead:boolean){
  if(protectedRead&&dirty&&!window.confirm('重新读取会替换未保存内容，是否继续？'))return;
  setBusy(true);try{
   const {response,value}=await request(`${protectedRead?'/api/sync/v1/garden-reviews':'/api/public/garden-reviews'}?asin=${encodeURIComponent(asin)}&categoryKey=${encodeURIComponent(categoryKey)}`,{headers:protectedRead?{Authorization:`Bearer ${secret}`}:{}});
   if(!response.ok)throw new Error(response.status===401?'同步凭证无效或没有读取权限':'核验读取失败，请稍后重试。');
   if(protectedRead){
    if(!value||!('latest' in value))throw new Error('核验数据格式异常');
    if(value.latest===null){setRevision(0);setDraft(emptyDraft());setPublished(false);setLegacy(false);setResult({message:'当前对象尚无核验版本，可以保存新的草稿。'});}
    else{
     const validated=validateGardenReview(value.latest);if(!validated.ok)throw new Error('核验数据未通过格式验证，原输入未被替换。');
     const record=validated.payload;setRevision(record.revision);setPublished(record.published);setLegacy(record.assessment.assessmentVersion!=='marketability_v2');
     setDraft({status:record.assessment.status,dimensions:record.assessment.dimensions,confirmed:false,salesBlocked:record.assessment.salesBlocked!==false,rejectionBasis:record.assessment.rejectionBasis??'market',reason:record.assessment.rejectionReason??''});
     setResult({message:`已读取版本 ${record.revision}，修改后需重新人工确认。`,status:record.assessment.status});
    }
    setDirty(false);setConflict(false);
   }else{
    if(!Array.isArray(value?.reviews))throw new Error('公开核验数据格式异常');
    const record=value.reviews.find((r:{asin:string;categoryKey:string})=>r.asin===asin&&r.categoryKey===categoryKey);
    setResult(record?{message:'已读取公开核验摘要；完整来源需要受保护读取。',status:record.status,issues:record.issues,summaries:Object.entries(record.dimensions??{}).map(([key,d])=>({name:names[key as keyof typeof names]??key,conclusion:(d as {conclusion:string}).conclusion,sourceCount:(d as {sourceCount:number}).sourceCount}))}:{message:'当前对象暂无已发布核验。'});
   }
  }catch(error){setResult({message:error instanceof Error&&error.name!=='AbortError'?error.message:'读取超时，请重试。'});}finally{setBusy(false);}
 }
 async function save(){
  if(!scopeValid||!secret||legacy||cannotPublish||conflict)return;
  setBusy(true);try{
   const assessment:GardenOpportunityRecord={assessmentVersion:'marketability_v2',reviewRevision:revision+1,confirmedReviewRevision:draft.confirmed?revision+1:undefined,salesBlocked:draft.salesBlocked,rejectionBasis:draft.rejectionBasis,completeMarketDays:0,confidencePassed:false,status:draft.status,dimensions:draft.dimensions,manualConfirmed:draft.confirmed,rejectionReason:draft.reason};
   const {response,value}=await request('/api/sync/v1/garden-reviews',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${secret}`},body:JSON.stringify({marketplace:'AMAZON_US',asin,categoryKey,revision:revision+1,previousRevision:revision,published,assessment})});
   if(response.status===409){setConflict(true);setResult({message:'版本冲突：服务器已有较新版本。当前输入已保留，请重新读取最新版本后核对。'});return;}
   if(!response.ok)throw new Error(response.status===401?'同步凭证无效或没有保存权限':response.status===400?'输入未通过验证，请核对当前对象、证据和版本。':'保存失败，请保留当前输入并重试。');
   if(value.status!=='saved'||!Number.isSafeInteger(value.revision)||!(value.assessment?.status in labels))throw new Error('保存响应异常，请重新读取服务器版本确认结果。');
   setRevision(value.revision);setDraft(previous=>({...previous,status:value.assessment.status,confirmed:false}));setDirty(false);setConflict(false);
   setResult({message:`版本 ${value.revision} 已保存${published?'，已提交公开摘要':'，未发布公开摘要'}。以服务器实际核验结果为准。`,status:value.assessment.status,issues:value.result?.issues??[]});
  }catch(error){setResult({message:error instanceof Error&&error.name!=='AbortError'?error.message:'保存请求超时，请先重新读取版本确认是否已保存。'});}finally{setBusy(false);}
 }
 return <div className="gardenEditor">
  <a target="_top" href={returnHref(params.get('returnTo'))}>← 返回商机列表</a>
  <div className="gardenFilters"><label>ASIN<input disabled={busy} value={asin} onChange={e=>resetScope({asin:e.target.value.toUpperCase()})} maxLength={10}/></label><label>所属榜单<select aria-label="所属榜单" disabled={busy} value={categoryKey} onChange={e=>resetScope({categoryKey:e.target.value})}><option value="">请选择榜单</option>{categories.map(c=><option key={c.key} value={c.key}>{c.label}</option>)}</select></label><label>同步凭证<input type="password" autoComplete="off" value={secret} onChange={e=>setSecret(e.target.value)}/></label></div>
  <p role="status">核验对象：{asin||'未选择'} · {categories.find(c=>c.key===categoryKey)?.label||'未选择榜单'} · 当前版本 {revision} · {dirty?'有未保存修改':'无未保存修改'}</p>
  {!scopeValid&&<p>请填写有效的 10 位 ASIN，并选择已注册的园艺榜单。</p>}
  <div className="gardenFilters"><button type="button" disabled={busy||!scopeValid} onClick={()=>load(false)}>读取公开核验</button><button type="button" disabled={busy||!secret||!scopeValid} onClick={()=>load(true)}>{conflict?'重新读取最新版本':'读取最新核验与版本'}</button></div>
  {legacy&&<section className="gardenPanel"><p>当前为旧口径核验，原版本保持不变且只读。新市场核验需要另存版本并重新确认。</p><button type="button" onClick={()=>{setLegacy(false);setPublished(false);setDraft(previous=>({...previous,dimensions:Object.fromEntries(MARKET_DIMENSIONS.filter(k=>previous.dimensions[k]).map(k=>[k,previous.dimensions[k]])),confirmed:false}));setDirty(true);}}>创建市场口径新版本</button></section>}
  <p>修改证据后须重新人工确认。经济性不参与当前市场可销售性判断，服务器仍独立验证真实市场数据与历史。</p>
  {MARKET_DIMENSIONS.map(key=>{const evidence=draft.dimensions[key];return <fieldset key={key} disabled={busy||legacy} className="reviewDimension"><legend>{names[key]}</legend>
   <label>证据结论<textarea aria-label="证据结论" maxLength={4000} value={evidence?.conclusion??''} onChange={e=>change({dimensions:{...draft.dimensions,[key]:{verified:false,conclusion:e.target.value,sources:evidence?.sources??[]}}})}/></label>
   {(evidence?.sources??[]).map((source,index)=><div className="reviewSource" key={index}><strong>来源 {index+1}</strong>
    <label>来源引用<input maxLength={2000} value={source.reference} onChange={e=>change({dimensions:editEvidenceSource(draft.dimensions,key,index,{reference:e.target.value})})}/></label>
    <label>来源日期<input type="date" value={source.date} onChange={e=>change({dimensions:editEvidenceSource(draft.dimensions,key,index,{date:e.target.value})})}/></label>
    <label>来源类型<select aria-label="来源类型" value={source.kind} onChange={e=>change({dimensions:editEvidenceSource(draft.dimensions,key,index,{kind:e.target.value as keyof typeof sourceKinds})})}>{Object.entries(sourceKinds).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label>
    <label>有效期至（可选）<input type="date" value={source.expiresAt??''} onChange={e=>change({dimensions:editEvidenceSource(draft.dimensions,key,index,{expiresAt:e.target.value||undefined})})}/></label>
    <button type="button" aria-label={`删除${names[key]}来源${index+1}`} onClick={()=>change({dimensions:removeEvidenceSource(draft.dimensions,key,index)})}>删除此来源</button>
   </div>)}
   <button type="button" disabled={(evidence?.sources.length??0)>=20} onClick={()=>change({dimensions:appendEvidenceSource(draft.dimensions,key)})}>添加{names[key]}来源</button>
   <label><input type="checkbox" checked={evidence?.verified??false} onChange={e=>change({dimensions:{...draft.dimensions,[key]:{verified:e.target.checked,conclusion:evidence?.conclusion??'',sources:evidence?.sources??[]}}})}/> 已核验该维度证据及适用条件</label>
  </fieldset>;})}
  <fieldset disabled={busy||legacy}><legend>核验结论与发布</legend>
   <label>核验状态<select aria-label="核验状态" value={draft.status} onChange={e=>change({status:e.target.value as Draft['status']})}>{Object.entries(labels).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label>
   <label><input type="checkbox" checked={!draft.salesBlocked} onChange={e=>change({salesBlocked:!e.target.checked})}/> 已核验可合法上架、配送及交付，未发现关键销售障碍</label>
   <label>暂不建议依据<select aria-label="暂不建议依据" value={draft.rejectionBasis} onChange={e=>change({rejectionBasis:e.target.value as Draft['rejectionBasis']})}><option value="market">市场需求或竞争证据</option><option value="sales_barrier">关键销售障碍</option></select></label>
   <label>暂不建议原因<input maxLength={4000} value={draft.reason} onChange={e=>change({reason:e.target.value})}/></label>
   <label><input type="checkbox" checked={draft.confirmed} onChange={e=>{setDraft(previous=>({...previous,confirmed:e.target.checked}));setDirty(true);}}/> 已人工确认当前版本的需求、竞争、差异化及销售可行性限制</label>
   <label><input type="checkbox" checked={published} onChange={e=>{setPublished(e.target.checked);setDirty(true);}}/> 发布该版本的公开摘要</label>
  </fieldset>
  {issues.length>0&&<section className="gardenPanel" aria-label="保存前检查"><h3>当前输入待核验项</h3><ul>{issues.map(issue=><li key={issue}>{issue}</li>)}</ul><p>可取消发布后保存为核验草稿；最终状态由服务器校验。</p></section>}
  <button type="button" disabled={busy||!secret||!scopeValid||legacy||cannotPublish||conflict} onClick={save}>{busy?'处理中…':'保存核验版本'}</button>
  <section className="gardenPanel" aria-live="polite"><h3>读取／保存结果</h3><p>{result?.message??'尚未读取或保存。'}</p>{result?.status&&<p>实际核验状态：{labels[result.status]??'待核验'}</p>}{result?.summaries?.map(s=><p key={s.name}><b>{s.name}</b> · {s.sourceCount} 项来源<br/>{s.conclusion}</p>)}{result?.issues&&result.issues.length>0&&<ul>{result.issues.map(issue=><li key={issue}>{issue}</li>)}</ul>}</section>
 </div>;
}
