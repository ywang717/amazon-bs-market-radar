"use client";
import { useEffect, useState } from "react";
import { useViewQuery } from "../components/useViewQuery";
import { readChoice } from "@/lib/view-state";
import { readPublishedReviews, type PublishedReview as Review } from "@/lib/garden-browser";
import { OPPORTUNITY_DIMENSION_LABELS, OPPORTUNITY_STATUS_HELP, OPPORTUNITY_STATUS_LABELS } from "@/lib/garden-opportunity-copy";
export function PublishedReviews({categories}:{categories:{key:string;label:string}[]}) {
 const {params,update}=useViewQuery();const [reviews,setReviews]=useState<Review[]>([]);const [error,setError]=useState(false);const [loading,setLoading]=useState(true);const [attempt,setAttempt]=useState(0);
 const category=readChoice(params,'reviewCategory',['',...categories.map(c=>c.key)],'');const status=readChoice(params,'reviewStatus',['',...Object.keys(OPPORTUNITY_STATUS_LABELS)],'');const asin=params.get('reviewAsin')??'';
 useEffect(()=>{let current=true;const controller=new AbortController();const timer=window.setTimeout(()=>controller.abort(),10000);
  fetch('/api/public/garden-reviews',{signal:controller.signal}).then(async response=>{if(!response.ok)throw new Error('unavailable');return response.json();}).then(value=>{
   const rows=readPublishedReviews(value);
   if(current)setReviews(rows);
  }).catch(()=>{if(current)setError(true);}).finally(()=>{window.clearTimeout(timer);if(current)setLoading(false);});
  return()=>{current=false;window.clearTimeout(timer);controller.abort();};
 },[attempt]);
 const visible=reviews.filter(r=>(!category||r.categoryKey===category)&&(!status||r.status===status)&&(!asin||r.asin.toLowerCase().includes(asin.trim().toLowerCase())));
 const clear=()=>update({reviewCategory:null,reviewStatus:null,reviewAsin:null});
 const returnTo=`/garden/opportunities?${params}`;
 return <section className="gardenPanel publishedReviews" aria-busy={loading}><h2>已发布人工核验</h2><p>与自动候选分别展示，仅包含已发布的最新核验摘要。</p><p className="opportunityStatusHelp">状态说明：{Object.entries(OPPORTUNITY_STATUS_LABELS).map(([key,label])=><span key={key}><strong>{label}</strong>：{OPPORTUNITY_STATUS_HELP[key as keyof typeof OPPORTUNITY_STATUS_HELP]}</span>)}</p>
  <div className="gardenFilters"><label>核验所属榜单<select aria-label="核验所属榜单" value={category} onChange={e=>update({reviewCategory:e.target.value})}><option value="">全部榜单</option>{categories.map(c=><option key={c.key} value={c.key}>{c.label}</option>)}</select></label><label>核验 ASIN<input value={asin} onChange={e=>update({reviewAsin:e.target.value},true)}/></label><label>核验结果<select aria-label="核验结果" value={status} onChange={e=>update({reviewStatus:e.target.value})}><option value="">全部状态</option>{Object.entries(OPPORTUNITY_STATUS_LABELS).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label><button type="button" onClick={clear}>清除核验筛选</button></div>
  {loading?<p role="status">正在读取核验结果…</p>:error?<div role="alert"><p>已发布核验暂时无法读取，读取失败不代表没有核验。</p><button type="button" onClick={()=>{setLoading(true);setError(false);setAttempt(value=>value+1);}}>重试读取核验</button></div>:!reviews.length?<p>暂无已发布核验。自动候选与人工核验分别展示。</p>:!visible.length?<p role="status">没有匹配的已发布核验，请调整或清除核验筛选。</p>:<><p role="status">共 {visible.length} 份匹配核验（最近读取 {reviews.length} 份）</p><div className="gardenCards">{visible.map(r=><article key={`${r.asin}-${r.categoryKey}`}><span className="gardenBadge">{OPPORTUNITY_STATUS_LABELS[r.status]??'待核验'}</span><h3>{r.asin} · {categories.find(c=>c.key===r.categoryKey)?.label??r.categoryKey}</h3><p>{OPPORTUNITY_STATUS_HELP[r.status]}</p><p>判断口径：{r.assessmentVersion==='marketability_v2'?'市场可销售性':'原五维度（含经济性）'} · 核验更新时间：{r.updatedAt}</p>{Object.entries(r.dimensions).filter(([key])=>key!=='economics').map(([key,d])=><p key={key}><b>{OPPORTUNITY_DIMENSION_LABELS[key]??key}</b> · {d.verified?'已核验':'待核验'} · {d.sourceCount} 项来源<br/>{d.conclusion}</p>)}{r.issues.length>0&&<p>待核验项：{r.issues.join('；')}</p>}<a target="_top" href={`/garden/review?asin=${encodeURIComponent(r.asin)}&categoryKey=${encodeURIComponent(r.categoryKey)}&returnTo=${encodeURIComponent(returnTo)}`}>查看核验 →</a></article>)}</div></>}
 </section>;
}
