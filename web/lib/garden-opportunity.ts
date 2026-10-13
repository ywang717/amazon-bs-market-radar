import { economicSourceValid, type EconomicSource, type GardenEconomicsResult } from './garden-economics.ts';
export const GARDEN_DIMENSIONS=['demand','competition','differentiation','economics','risk'] as const;
export type GardenOpportunityStatus='observation'|'pending_verification'|'worth_validating'|'not_recommended';
export type GardenEvidence={verified:boolean;conclusion:string;sources:EconomicSource[];};
export type GardenOpportunityRecord={completeMarketDays:number;confidencePassed:boolean;status:GardenOpportunityStatus;dimensions:Partial<Record<typeof GARDEN_DIMENSIONS[number],GardenEvidence>>;economics?:GardenEconomicsResult;economicsRevision:number;confirmedEconomicsRevision?:number;manualConfirmed:boolean;asOf?:string;rejectionReason?:string;};
export function evaluateGardenOpportunity(record:GardenOpportunityRecord){
 const issues:string[]=[];const asOf=record.asOf??new Date().toISOString().slice(0,10);
 if(record.completeMarketDays<7)issues.push('至少需要7个完整市场日');if(!record.confidencePassed)issues.push('初筛置信度不足');
 for(const name of GARDEN_DIMENSIONS){const evidence=record.dimensions[name];if(!evidence?.verified||!evidence.conclusion?.trim()||!evidence.sources?.length||evidence.sources.some(source=>!economicSourceValid(source,asOf)))issues.push(`${name}证据待核验`);}
 if(!record.economics?.complete||!record.economics.verified)issues.push('经济性输入未全部核验');
 if(record.economics?.netProfit && (record.economics.netProfit.startsWith('-') || Number(record.economics.netProfit)===0))issues.push('经济性未显示正利润');
 if(record.economics?.revision!==record.economicsRevision||record.confirmedEconomicsRevision!==record.economicsRevision)issues.push('经济性已修改，需重新确认');
 if(!record.manualConfirmed)issues.push('尚未人工确认');
 let status:GardenOpportunityStatus='pending_verification';
 if(record.status==='observation')status='observation';
 else if(record.status==='not_recommended'&&record.rejectionReason?.trim())status='not_recommended';
 else if(record.status==='worth_validating'&&issues.length===0)status='worth_validating';
 return {status,eligibleForAutomaticCandidate:record.completeMarketDays>=7&&record.confidencePassed,issues};
}
