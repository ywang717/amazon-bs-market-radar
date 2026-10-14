import { economicSourceValid, type EconomicSource, type GardenEconomicsResult } from './garden-economics.ts';
export const GARDEN_DIMENSIONS=['demand','competition','differentiation','economics','risk'] as const;
export const MARKET_DIMENSIONS=['demand','competition','differentiation','risk'] as const;
export type GardenOpportunityStatus='observation'|'pending_verification'|'worth_validating'|'not_recommended';
export type GardenEvidence={verified:boolean;conclusion:string;sources:EconomicSource[];};
export type GardenOpportunityRecord={completeMarketDays:number;confidencePassed:boolean;status:GardenOpportunityStatus;dimensions:Partial<Record<typeof GARDEN_DIMENSIONS[number],GardenEvidence>>;economics?:GardenEconomicsResult;assessmentVersion?:'legacy_v1'|'marketability_v2';reviewRevision?:number;confirmedReviewRevision?:number;economicsRevision?:number;confirmedEconomicsRevision?:number;salesBlocked?:boolean;rejectionBasis?:'market'|'sales_barrier';manualConfirmed:boolean;asOf?:string;rejectionReason?:string;};
export function evaluateGardenOpportunity(record:GardenOpportunityRecord){
 const issues:string[]=[];const asOf=record.asOf??new Date().toISOString().slice(0,10);
 if(record.completeMarketDays<7)issues.push('至少需要7个完整市场日');if(!record.confidencePassed)issues.push('初筛置信度不足');
 const marketOnly=record.assessmentVersion==='marketability_v2';
 for(const name of marketOnly?MARKET_DIMENSIONS:GARDEN_DIMENSIONS){const evidence=record.dimensions[name];if(!evidence?.verified||!evidence.conclusion?.trim()||!evidence.sources?.length||evidence.sources.some(source=>!economicSourceValid(source,asOf)))issues.push(`${name}证据待核验`);}
 if(marketOnly){if(record.salesBlocked!==false)issues.push('销售可行性存在障碍或待确认');if(!Number.isSafeInteger(record.reviewRevision)||record.reviewRevision!==record.confirmedReviewRevision)issues.push('核验版本已修改，需重新确认');}
 else {
 if(!record.economics?.complete||!record.economics.verified)issues.push('经济性输入未全部核验');
 if(record.economics?.netProfit && (record.economics.netProfit.startsWith('-') || Number(record.economics.netProfit)===0))issues.push('经济性未显示正利润');
 if(record.economics?.revision!==record.economicsRevision||record.confirmedEconomicsRevision!==record.economicsRevision)issues.push('经济性已修改，需重新确认');
 }
 if(!record.manualConfirmed)issues.push('尚未人工确认');
 let status:GardenOpportunityStatus='pending_verification';
 if(record.status==='observation')status='observation';
 else if(record.status==='not_recommended'&&record.rejectionReason?.trim()&&(!marketOnly||record.rejectionBasis==='market'||record.rejectionBasis==='sales_barrier')){const keys=record.rejectionBasis==='sales_barrier'?['risk']:['demand','competition'];const supported=keys.some(k=>{const e=record.dimensions[k as typeof GARDEN_DIMENSIONS[number]];return e?.verified&&e.conclusion.trim()&&e.sources.length&&e.sources.every(s=>economicSourceValid(s,asOf));});if(!marketOnly||(supported&&record.manualConfirmed&&record.reviewRevision===record.confirmedReviewRevision&&(record.rejectionBasis!=='sales_barrier'||record.salesBlocked===true)))status='not_recommended';else issues.push('暂不建议需可追溯市场或销售障碍证据及当前版本人工确认');}
 else if(record.status==='worth_validating'&&issues.length===0)status='worth_validating';
 return {status,eligibleForAutomaticCandidate:record.completeMarketDays>=7&&record.confidencePassed,issues};
}
