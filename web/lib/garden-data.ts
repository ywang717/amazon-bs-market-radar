import { productionCategoryRegistry } from './category-registry.ts';
import { validateCategory } from './analytics.ts';
import type { ObservationRow, ProductMetadataRow, CategoryDayRow } from './dashboard-store.ts';
export type GardenProduct = {asin:string;title:string;url:string;price:number|null;rating:number|null;reviews:number|null;rank:number;rankChange:number|null;reviewGrowth:number|null;priceChange:number|null;history:{marketDate:string;rank:number;price:number|null;reviews:number|null}[];signals:string[];confidence:number;candidate:boolean;brand:string|null;score:number|null};
export type GardenCategory = {key:string;label:string;sourceUrl:string;enabled:boolean;marketDate:string|null;completeMarketDays:number;latestComplete:boolean;products:GardenProduct[]};
export type GardenData = {latestMarketDate:string|null;categories:GardenCategory[];weeklyReports:{key:string;title:string;marketDate:string;categoryKey:string|null}[];error?:string};
type GardenRegistry = {categoryKey:string;labelZh:string;sourceUrl:string;enabled:boolean;groupKey?:string};
export function meetsGardenCandidateThresholds(completeDays:number, confidence:number, score:number|null, signalCount:number) {
 return completeDays>=7&&confidence>=50&&score!==null&&score>=45&&signalCount>0;
}
export function buildGardenData(input:{categories:readonly GardenRegistry[];categoryDays:readonly Pick<CategoryDayRow,'market_date'|'category_key'|'complete'>[];observations:readonly ObservationRow[];metadata:readonly ProductMetadataRow[];latestMarketDate?:string|null}):GardenData {
 const latestMarketDate=input.latestMarketDate??input.categoryDays.map(d=>d.market_date).sort().at(-1)??null;
 const categories=input.categories.map((category):GardenCategory=>{
  const rows=input.observations.filter(r=>r.category_key===category.categoryKey);
  const dates=[...new Set(input.categoryDays.filter(d=>d.category_key===category.categoryKey&&d.complete===1).map(d=>d.market_date))].sort().filter(date=>validateCategory(rows.filter(r=>r.market_date===date)).complete);
  const marketDate=dates.at(-1)??null; const windowDates=dates.slice(-7);
  const products=rows.filter(r=>r.market_date===marketDate).map((row):GardenProduct=>{
   const history=rows.filter(r=>r.asin===row.asin&&windowDates.includes(r.market_date)).sort((a,b)=>a.market_date.localeCompare(b.market_date)).map(r=>({marketDate:r.market_date,rank:r.rank,price:r.price,reviews:r.reviews}));
   const first=history[0];const comparable=history.length>=2;
   const rankChange=comparable?first.rank-row.rank:null;
   const reviewGrowth=comparable&&first.reviews!==null&&row.reviews!==null&&row.reviews>=first.reviews?row.reviews-first.reviews:null;
   const priceChange=comparable&&first.price!==null&&row.price!==null?row.price-first.price:null;
   const signals:string[]=[];
   if(rankChange!==null&&rankChange>=20)signals.push('排名快速提升');
   if(history.some((h,i)=>i>0&&Math.abs(h.rank-history[i-1].rank)>=20))signals.push('短期大幅波动，需核查促销');
   if(comparable&&first.reviews!==null&&row.reviews!==null&&row.reviews<first.reviews)signals.push('评论数回落，需核查数据异常');
   if(row.rank<=20&&row.reviews!==null&&row.reviews<=500)signals.push('高排名低评论');
   const newEntry=windowDates.length>=2&&!rows.some(r=>r.asin===row.asin&&r.market_date===windowDates[0]);
   if(newEntry)signals.push('窗口内新入榜');
   const reviewsPerDay=reviewGrowth===null?null:reviewGrowth/Math.max(1,history.length-1);
   if(reviewsPerDay!==null&&reviewsPerDay>=10)signals.push('评论增长较快');
   let available=0,total=0;
   if(rankChange!==null){available+=30;total+=Math.max(0,Math.min(100,rankChange/20*100))*30;}
   if(reviewsPerDay!==null){available+=20;total+=Math.min(100,reviewsPerDay/10*100)*20;}
   if(row.rating!==null){available+=15;total+=Math.max(0,Math.min(100,(row.rating-3.5)/1.5*100))*15;}
   if(windowDates.length>=2){available+=15;total+=(newEntry?100:0)*15;}
   // Brand growth unavailable: do not invent it from title or present brand concentration.
   const confidence=Math.round(available*Math.min(1,history.length/7));
   const score=available?Math.round(total/available):null;
   const metadata=input.metadata.find(m=>m.asin===row.asin);
   return {...row,rankChange,reviewGrowth,priceChange,history,signals,confidence,score,candidate:meetsGardenCandidateThresholds(windowDates.length,confidence,score,signals.length),brand:metadata?.brandSource==='verified_metadata'?metadata.normalizedBrand:null};
  });
  return {key:category.categoryKey,label:category.labelZh,sourceUrl:category.sourceUrl,enabled:category.enabled,marketDate,completeMarketDays:dates.length,latestComplete:marketDate!==null&&marketDate===latestMarketDate,products};
 });
 return {latestMarketDate,categories,weeklyReports:[]};
}
export function gardenRegistryCategories():readonly GardenRegistry[] {
 return productionCategoryRegistry.categories.filter(c=>(c as GardenRegistry).groupKey==='patio_lawn_garden'||c.categoryKey==='patio_lawn_garden'||c.categoryKey.startsWith('garden_'));
}
export async function loadGardenData():Promise<GardenData> {
 const categories=gardenRegistryCategories();
 try {
  const {getD1,ensureSchema}=await import('./d1.ts'); const db=getD1();await ensureSchema(db);
  // Scope queries to garden and bound history; old project records are untouched.
  const keys=categories.map(c=>c.categoryKey); if(!keys.length)return {latestMarketDate:null,categories:[],weeklyReports:[]};
  const placeholders=keys.map(()=>'?').join(',');
  const latest=await db.prepare('SELECT MAX(market_date) AS date FROM category_days').first<{date:string|null}>();
  const [days,observations,metadata,reports]=await Promise.all([
   db.prepare(`SELECT market_date,category_key,complete FROM category_days WHERE category_key IN (${placeholders}) AND market_date>=date(?,'-90 days')`).bind(...keys,latest?.date??'1970-01-01').all<CategoryDayRow>(),
   db.prepare(`SELECT market_date,category_key,rank,asin,title,url,price,rating,reviews FROM observations WHERE category_key IN (${placeholders}) AND market_date>=date(?,'-90 days') ORDER BY market_date,category_key,rank`).bind(...keys,latest?.date??'1970-01-01').all<ObservationRow>(),
   db.prepare(`SELECT DISTINCT m.asin,m.normalized_brand,m.brand_source FROM product_metadata m JOIN observations o ON o.asin=m.asin WHERE m.marketplace='AMAZON_US' AND o.category_key IN (${placeholders})`).bind(...keys).all<{asin:string;normalized_brand:string|null;brand_source:string}>(),
   db.prepare(`SELECT key,title,market_date,category_key FROM reports WHERE kind='weekly' AND category_key IN (${placeholders}) ORDER BY market_date DESC LIMIT 30`).bind(...keys).all<{key:string;title:string;market_date:string;category_key:string|null}>(),
  ]);
  const data=buildGardenData({categories,categoryDays:days.results,observations:observations.results,metadata:metadata.results.map(m=>({asin:m.asin,normalizedBrand:m.normalized_brand,brandSource:m.brand_source} as ProductMetadataRow)),latestMarketDate:latest?.date});
  return {...data,weeklyReports:reports.results.map(r=>({key:r.key,title:r.title,marketDate:r.market_date,categoryKey:r.category_key}))};
 }catch(error){console.error('garden_data_unavailable',error);return {...buildGardenData({categories,categoryDays:[],observations:[],metadata:[]}),error:'数据暂时无法读取，请稍后重试。'};}
}
