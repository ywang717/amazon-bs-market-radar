import type { GardenCategory } from './garden-data.ts';
export type GardenFilters = {categoryKey?:string;q?:string;signal?:string;sort?:string;minPrice?:string;maxPrice?:string};
function gardenMemberships(categories:GardenCategory[], categoryKey:string|undefined, opportunities:boolean) {
 return categories.filter(c=>!categoryKey||c.key===categoryKey).flatMap(c=>c.products.filter(p=>!opportunities||(c.completeMarketDays>=7&&p.candidate)).map(p=>({...p,category:c})));
}
export function gardenSignalOptions(categories:GardenCategory[],categoryKey:string,opportunities:boolean) {
 return [...new Set(gardenMemberships(categories,categoryKey,opportunities).flatMap(p=>p.signals))];
}
export function selectGardenProducts(categories: GardenCategory[], filters: GardenFilters, opportunities: boolean) {
 const memberships=gardenMemberships(categories,filters.categoryKey,opportunities);
 const min=filters.minPrice?Number(filters.minPrice):null,max=filters.maxPrice?Number(filters.maxPrice):null;
 const query=(filters.q??'').trim().toLowerCase();
 const rows=memberships.filter(p=>(!query||`${p.asin} ${p.title} ${p.brand??''}`.toLowerCase().includes(query))&&(!filters.signal||p.signals.includes(filters.signal))&&(min===null||(p.price!==null&&p.price>=min))&&(max===null||(p.price!==null&&p.price<=max))).sort((a,b)=>filters.sort==='score'?(b.score??-1)-(a.score??-1)||b.confidence-a.confidence:filters.sort==='confidence'?b.confidence-a.confidence:filters.sort==='price'?(a.price??Infinity)-(b.price??Infinity):a.rank-b.rank);
 const seen=new Set<string>();return rows.filter(p=>{if(seen.has(p.asin))return false;seen.add(p.asin);return true;});
}
export function gardenEmptyReason(categories: Pick<GardenCategory,'completeMarketDays'>[], opportunities:boolean, failed:boolean, eligible:number, visible:number) {
 if(failed)return 'error';
 if(opportunities&&!categories.some(c=>c.completeMarketDays>=7))return 'insufficient';
 if(opportunities&&eligible===0)return 'threshold';
 return visible===0?'filtered':'ready';
}

export type PublishedReview = {asin:string;categoryKey:string;status:'observation'|'pending_verification'|'worth_validating'|'not_recommended';updatedAt:string;assessmentVersion?:string;issues:string[];dimensions:Record<string,{verified:boolean;conclusion:string;sourceCount:number}>};
export function readPublishedReviews(value:unknown):PublishedReview[] {
 const rows=value&&typeof value==='object'&&'reviews' in value?value.reviews:null;
 if(!Array.isArray(rows)||rows.some(r=>!r||typeof r.asin!=='string'||typeof r.categoryKey!=='string'||typeof r.updatedAt!=='string'||!['observation','pending_verification','worth_validating','not_recommended'].includes(r.status)||!Array.isArray(r.issues)||r.issues.some((issue:unknown)=>typeof issue!=='string')||!r.dimensions||typeof r.dimensions!=='object'||Array.isArray(r.dimensions)||Object.values(r.dimensions).some(d=>!d||typeof d!=='object'||!('verified' in d)||typeof d.verified!=='boolean'||!('conclusion' in d)||typeof d.conclusion!=='string'||!('sourceCount' in d)||!Number.isSafeInteger(d.sourceCount)||Number(d.sourceCount)<0)))throw new Error('已发布核验数据格式异常');
 return rows as PublishedReview[];
}
