import { GARDEN_COST_CATEGORIES, type GardenEconomicsInput } from './garden-economics.ts';
import { GARDEN_DIMENSIONS, type GardenOpportunityRecord } from './garden-opportunity.ts';
export type GardenReviewPayload={marketplace:'AMAZON_US';asin:string;categoryKey:string;revision:number;previousRevision:number;published:boolean;economicsInput:GardenEconomicsInput;assessment:GardenOpportunityRecord};
function object(v:unknown):v is Record<string,unknown>{return !!v&&typeof v==='object'&&!Array.isArray(v);}
function source(v:unknown){return object(v)&&typeof v.reference==='string'&&v.reference.length<=2000&&typeof v.date==='string'&&['invoice','settlement','order','quote','official_fee','assumption','exchange_rate'].includes(String(v.kind))&&(v.expiresAt===undefined||typeof v.expiresAt==='string');}
function economic(v:unknown):boolean {
 if(!object(v)||!['verified','assumption','missing','not_applicable'].includes(String(v.status)))return false;
 if(v.amount!==null&&(typeof v.amount!=='string'||!/^\d{1,15}(?:\.\d{1,12})?$/.test(v.amount)))return false;
 if(!['currency','unit','specification','conditions'].every(k=>typeof v[k]==='string'&&(v[k] as string).length<=4000))return false;
 if(v.notApplicableReason!==undefined&&(typeof v.notApplicableReason!=='string'||v.notApplicableReason.length>4000))return false;
 if(v.source!==undefined&&!source(v.source))return false;
 if(v.quantity!==undefined&&(typeof v.quantity!=='string'||!/^\d{1,12}$/.test(v.quantity)))return false;
 if(v.fx!==undefined&&(!object(v.fx)||typeof v.fx.rate!=='string'||!/^\d{1,12}(?:\.\d{1,12})?$/.test(v.fx.rate)||!source(v.fx.source)))return false;
 return true;
}
export function validateGardenReview(value:unknown):{ok:true;payload:GardenReviewPayload}|{ok:false;error:string} {
 const fail=()=>({ok:false as const,error:'invalid_garden_review'});
 if(!object(value)||value.marketplace!=='AMAZON_US'||typeof value.asin!=='string'||!/^B[A-Z0-9]{9}$/.test(value.asin)||typeof value.categoryKey!=='string'||!/^\w{1,80}$/.test(value.categoryKey))return fail();
 if(!Number.isSafeInteger(value.revision)||!Number.isSafeInteger(value.previousRevision)||Number(value.previousRevision)<0||value.revision!==Number(value.previousRevision)+1||typeof value.published!=='boolean')return fail();
 const input=value.economicsInput;
 if(!object(input)||!['forecast','actual'].includes(String(input.mode))||typeof input.currency!=='string'||input.currency!=='USD'||typeof input.asOf!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(input.asOf)||input.revision!==value.revision||!economic(input.salePrice)||!Array.isArray(input.costs)||input.costs.length>GARDEN_COST_CATEGORIES.length)return fail();
 if(input.costs.some(c=>!economic(c)||!object(c)||!GARDEN_COST_CATEGORIES.includes(c.category as typeof GARDEN_COST_CATEGORIES[number])||!['per_unit','batch','percent_revenue'].includes(String(c.basis))||(c.includes!==undefined&&(!Array.isArray(c.includes)||c.includes.some((k: unknown)=>!GARDEN_COST_CATEGORIES.includes(k as typeof GARDEN_COST_CATEGORIES[number]))))))return fail();
 if(input.scenarios!==undefined&&(!Array.isArray(input.scenarios)||input.scenarios.length>20||input.scenarios.some(s=>!object(s)||typeof s.label!=='string'||s.label.length>200||typeof s.salePrice!=='string'||!/^\d{1,15}(?:\.\d{1,12})?$/.test(s.salePrice)||['advertising','returns'].some(k=>s[k]!==undefined&&(typeof s[k]!=='string'||!/^\d{1,15}(?:\.\d{1,12})?$/.test(s[k] as string))))))return fail();
 const a=value.assessment;
 if(!object(a)||!['observation','pending_verification','worth_validating','not_recommended'].includes(String(a.status))||!object(a.dimensions)||typeof a.manualConfirmed!=='boolean'||a.economicsRevision!==value.revision||(a.confirmedEconomicsRevision!==undefined&&a.confirmedEconomicsRevision!==value.revision)||(a.rejectionReason!==undefined&&(typeof a.rejectionReason!=='string'||a.rejectionReason.length>4000)))return fail();
 if(Object.keys(a.dimensions).some(k=>!GARDEN_DIMENSIONS.includes(k as typeof GARDEN_DIMENSIONS[number])))return fail();
 for(const k of GARDEN_DIMENSIONS){const d=a.dimensions[k];if(d!==undefined&&(!object(d)||typeof d.verified!=='boolean'||typeof d.conclusion!=='string'||d.conclusion.length>4000||!Array.isArray(d.sources)||d.sources.length>20||d.sources.some(s=>!source(s))))return fail();}
 return {ok:true,payload:value as unknown as GardenReviewPayload};
}
