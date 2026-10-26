"use client";
import type { GardenCategory } from "@/lib/garden-data";
import { gardenEmptyReason, gardenSignalOptions, selectGardenProducts } from "@/lib/garden-browser";
import { pageRows, readChoice } from "@/lib/view-state";
import { useViewQuery } from "../components/useViewQuery";
import { ListPagination } from "../components/ListPagination";

export function ProductBrowser({ categories, opportunities = false, error, updatedAt, updatedMarketDate }: {categories:GardenCategory[];opportunities?:boolean;error?:string;updatedAt?:string|null;updatedMarketDate?:string|null}) {
 const {params,update}=useViewQuery();
 const categoryKey=readChoice(params,'categoryKey',['',...categories.map(c=>c.key)],'');
 const signals=gardenSignalOptions(categories,categoryKey,opportunities);
 const signal=readChoice(params,'signal',['',...signals],'');
 const sort=readChoice(params,'sort',['score','rank','confidence','price'],opportunities?'score':'rank');
 const q=params.get('q')??'',minPrice=params.get('minPrice')??'',maxPrice=params.get('maxPrice')??'';
 const invalidPrice=[minPrice,maxPrice].some(v=>v!==''&&(!Number.isFinite(Number(v))||Number(v)<0))||!!(minPrice&&maxPrice&&Number(minPrice)>Number(maxPrice));
 const products=invalidPrice?[]:selectGardenProducts(categories,{categoryKey,signal,sort,q,minPrice,maxPrice},opportunities);
 const pagination=pageRows(products,params.get('page'),30);
 const eligible=selectGardenProducts(categories,{sort},opportunities).length;
 const empty=gardenEmptyReason(categories,opportunities,!!error,eligible,products.length);
 const reset=()=>update({categoryKey:null,signal:null,sort:null,q:null,minPrice:null,maxPrice:null,page:null});
 const filter=(changes:Record<string,string|null>)=>update({...changes,page:null});
 const returnTo=`${opportunities?'/garden/opportunities':'/garden/products'}?${params}`;
 return <>
  {opportunities&&<div className="gardenPanel opportunityGuide"><h3>自动候选怎么读</h3><p>这里展示的是研究线索：先看入选信号和数据依据，再检查证据缺口。只有完成需求、竞争、差异化和销售可行性限制的人工核验，才会形成已发布结论。</p><p>园艺最新完整市场日：{categories.map(c=>c.marketDate).filter(Boolean).sort().at(-1)??'暂无'}。各候选的实际市场日见卡片。全站采集市场日：{updatedMarketDate??'暂无'} · 全站采集时间：{updatedAt?new Intl.DateTimeFormat('zh-CN',{timeZone:'America/Los_Angeles',dateStyle:'medium',timeStyle:'medium'}).format(new Date(updatedAt))+' (Pacific Time)':'暂无记录'} · 研究优先级不代表成交概率或销量预测。</p></div>}
  <div className="gardenFilters">
   <label>所属榜单<select aria-label="所属榜单" value={categoryKey} onChange={e=>filter({categoryKey:e.target.value,signal:null})}><option value="">全部榜单</option>{categories.map(c=><option key={c.key} value={c.key}>{c.label}</option>)}</select></label>
   <label>机会信号<select aria-label="机会信号" value={signal} onChange={e=>filter({signal:e.target.value})}><option value="">全部信号</option>{signals.map(s=><option key={s}>{s}</option>)}</select></label>
   <label>搜索产品或 ASIN<input value={q} onChange={e=>update({q:e.target.value,page:null},true)}/></label>
   <label>最低价格（USD）<input type="number" min="0" step="0.01" value={minPrice} onChange={e=>filter({minPrice:e.target.value})}/></label>
   <label>最高价格（USD）<input type="number" min="0" step="0.01" value={maxPrice} onChange={e=>filter({maxPrice:e.target.value})}/></label>
   <label>排序<select aria-label="排序" value={sort} onChange={e=>filter({sort:e.target.value})}><option value="score">初筛评分</option><option value="rank">榜单排名</option><option value="confidence">置信度</option><option value="price">价格从低到高</option></select></label>
   <button type="button" onClick={reset}>清除筛选</button>
  </div>
  {invalidPrice&&<p role="alert">请输入有效价格区间，最低价格不能高于最高价格。</p>}
  <p role="status">共 {products.length} 条{opportunities?'去重候选':'榜单记录'}</p>
  {opportunities&&<p className="gardenNotice">初筛评分仅用于研究优先级，置信度不代表成交概率。自动线索与已发布人工核验分别展示。</p>}
  {(error||!products.length)&&<div className="gardenEmpty" role={error?'alert':'status'}>
   <h3>{empty==='error'?'商机数据读取失败':empty==='insufficient'?'完整市场日不足':empty==='threshold'?'暂无达到初筛条件的候选':opportunities?'没有匹配的商机':'暂无匹配产品'}</h3>
   <p>{empty==='error'?'数据服务暂时不可用，读取失败不代表没有商机。':empty==='insufficient'?`当前最多 ${Math.max(0,...categories.map(c=>c.completeMarketDays))} 个完整市场日，至少需要 7 个；请等待真实数据积累。`:empty==='threshold'?'当前没有同时达到现有评分、置信度和信号要求的候选，不降低门槛生成结论。':'请调整关键词、所属榜单、信号或价格区间。'}</p>
   {empty==='error'?<button type="button" onClick={()=>window.location.reload()}>重试读取数据</button>:<><button type="button" onClick={reset}>清除当前筛选</button> <a target="_top" href="/garden">查看市场数据 →</a></>}
  </div>}
  {!error&&<div className="gardenCards">{pagination.rows.map(p=>{
   const gaps=[p.price===null?'价格':null,p.rating===null?'评分':null,p.reviews===null?'评论数':null,p.rankChange===null?'可比较排名历史':null].filter(Boolean);
   return <article key={`${p.category.key}-${p.asin}`}><span className="gardenBadge">{p.category.label} · #{p.rank}</span><h3><a href={p.url} target="_blank" rel="noreferrer">{p.title}</a></h3>
    <p>所属榜单：{categories.flatMap(c=>c.products.filter(x=>x.asin===p.asin).map(x=>`${c.label} #${x.rank}`)).join('；')}</p>
    <p>{p.asin} · 数据截至 {p.category.marketDate||'日期未知'}{!p.category.latestComplete&&' · 最近采集不完整'}</p>
    <dl className="gardenMetrics"><div><dt>价格</dt><dd>{p.price===null?'缺失':`$${p.price}`}</dd></div><div><dt>评分 / 评论</dt><dd>{p.rating??'—'} / {p.reviews??'—'}</dd></div><div><dt>排名提升</dt><dd>{p.rankChange??'—'}</dd></div><div><dt>评论增长</dt><dd>{p.reviewGrowth??'—'}</dd></div></dl>
    {opportunities&&<><section className="opportunityCardSection"><strong>为什么入选</strong><p>{p.signals.join(' · ')||'达到现有商机初筛规则'}</p></section><section className="opportunityCardSection"><strong>数据依据</strong><p>初筛评分 {p.score??'—'} · 置信度 {p.confidence} · {p.category.completeMarketDays} 个完整市场日</p><p>指标比较区间：{p.history[0]?.marketDate??'不足'} 至 {p.history.at(-1)?.marketDate??'不足'} · {p.history.length} 条观测</p></section><section className="opportunityCardSection"><strong>还需核验</strong><p>指标缺口：{gaps.length?gaps.join('、'):'当前展示指标无缺失'}</p><p>需求、竞争、差异化及销售障碍仍需人工核验。</p></section><a target="_top" href={`/garden/review?asin=${encodeURIComponent(p.asin)}&categoryKey=${encodeURIComponent(p.category.key)}&returnTo=${encodeURIComponent(returnTo)}`}>进入人工核验 →</a></>}
    <details><summary>同榜单历史 ({p.history.length})</summary><div className="gardenTable"><table><thead><tr><th>市场日</th><th>排名</th><th>价格</th><th>评论数</th></tr></thead><tbody>{p.history.map(h=><tr key={h.marketDate}><td>{h.marketDate}</td><td>{h.rank??'—'}</td><td>{h.price===null?'—':`$${h.price}`}</td><td>{h.reviews??'—'}</td></tr>)}</tbody></table></div></details>
   </article>;
  })}</div>}
  {!error&&products.length>0&&<ListPagination {...pagination} onPage={page=>update({page})} label={opportunities?'商机候选分页':'园艺产品分页'}/>}
 </>;
}
