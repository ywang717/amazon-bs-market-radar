import { env } from 'cloudflare:workers';
import { authorizeSyncRequest } from '@/lib/sync-auth';
import { getD1,ensureSchema } from '@/lib/d1';
import { validateGardenReview } from '@/lib/garden-review-contract';
import { calculateGardenEconomics } from '@/lib/garden-economics';
import { evaluateGardenOpportunity } from '@/lib/garden-opportunity';
import { loadGardenData,gardenRegistryCategories } from '@/lib/garden-data';
const noStore={'cache-control':'no-store'};
export async function GET(request:Request){
 if(!authorizeSyncRequest(request,env.SYNC_SECRET as string|undefined))return Response.json({error:'unauthorized'},{status:401,headers:noStore});
 const query=new URL(request.url).searchParams;const asin=query.get('asin'),categoryKey=query.get('categoryKey');
 if(!asin||!/^B[A-Z0-9]{9}$/.test(asin)||!gardenRegistryCategories().some(c=>c.categoryKey===categoryKey))return Response.json({error:'invalid_scope'},{status:400});
 try{const db=getD1();await ensureSchema(db);const rows=await db.prepare("SELECT revision,content_json,updated_at FROM garden_review_versions WHERE marketplace='AMAZON_US' AND asin=? AND category_key=? ORDER BY revision DESC").bind(asin,categoryKey).all<{revision:number;content_json:string;updated_at:string}>();return Response.json({latest:rows.results[0]?JSON.parse(rows.results[0].content_json):null,history:rows.results.map(r=>({revision:r.revision,updatedAt:r.updated_at}))},{headers:noStore});}catch{return Response.json({error:'review_unavailable'},{status:503,headers:noStore});}
}
export async function POST(request:Request){
 if(!authorizeSyncRequest(request,env.SYNC_SECRET as string|undefined))return Response.json({error:'unauthorized'},{status:401,headers:noStore});
 let raw:unknown;try{const text=await request.text();if(text.length>150000)return Response.json({error:'payload_too_large'},{status:413});raw=JSON.parse(text);}catch{return Response.json({error:'invalid_json'},{status:400});}
 const validated=validateGardenReview(raw);if(!validated.ok)return Response.json({error:validated.error},{status:400});
 const p=validated.payload;if(!gardenRegistryCategories().some(c=>c.categoryKey===p.categoryKey))return Response.json({error:'invalid_scope'},{status:400});
 try{
 const db=getD1();await ensureSchema(db);const data=await loadGardenData();if(data.error)return Response.json({error:'market_data_unavailable'},{status:503});
 const category=data.categories.find(c=>c.key===p.categoryKey);const product=category?.products.find(r=>r.asin===p.asin);
 const today=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Los_Angeles',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 if(p.economicsInput.asOf!==today)return Response.json({error:'economic_date_must_be_current',marketDate:today},{status:400});
 const economics=calculateGardenEconomics(p.economicsInput);
 const assessment={status:p.assessment.status,dimensions:p.assessment.dimensions,manualConfirmed:p.assessment.manualConfirmed,rejectionReason:p.assessment.rejectionReason,confirmedEconomicsRevision:p.assessment.confirmedEconomicsRevision,asOf:today,completeMarketDays:category?.completeMarketDays??0,confidencePassed:!!product&&product.confidence>=50&&product.candidate,economics,economicsRevision:p.revision};
 // Every saved revision represents new inputs; a previous confirmation cannot silently carry over.
 const previous=await db.prepare("SELECT content_json FROM garden_review_versions WHERE marketplace=? AND asin=? AND category_key=? AND revision=?").bind(p.marketplace,p.asin,p.categoryKey,p.previousRevision).first<{content_json:string}>();
 if(previous){const old=JSON.parse(previous.content_json);if(JSON.stringify(old.economicsInput)!==JSON.stringify(p.economicsInput)&&p.assessment.confirmedEconomicsRevision===p.previousRevision){assessment.manualConfirmed=false;assessment.confirmedEconomicsRevision=undefined;}}
 const result=evaluateGardenOpportunity(assessment);
 const stored={...p,assessment:{...assessment,status:result.status},result};
 const publicRecord={marketplace:p.marketplace,asin:p.asin,categoryKey:p.categoryKey,revision:p.revision,status:result.status,issues:result.issues,dimensions:Object.fromEntries(Object.entries(assessment.dimensions).map(([key,d])=>[key,{verified:d?.verified,conclusion:d?.conclusion,sourceCount:d?.sources.length??0}])),economics:{mode:economics.mode,complete:economics.complete,verified:economics.verified,hasAssumptions:economics.hasAssumptions,...(economics.complete?{netProfit:economics.netProfit,netMarginPercent:economics.netMarginPercent,breakEvenPrice:economics.breakEvenPrice}:{}),issues:economics.issues},updatedAt:new Date().toISOString()};
 const write=await db.prepare(`INSERT INTO garden_review_versions(marketplace,asin,category_key,revision,published,status,content_json,public_json,updated_at) SELECT ?,?,?,?,?,?,?,?,? WHERE COALESCE((SELECT MAX(revision) FROM garden_review_versions WHERE marketplace=? AND asin=? AND category_key=?),0)=? ON CONFLICT DO NOTHING`).bind(p.marketplace,p.asin,p.categoryKey,p.revision,p.published?1:0,result.status,JSON.stringify(stored),JSON.stringify(publicRecord),publicRecord.updatedAt,p.marketplace,p.asin,p.categoryKey,p.previousRevision).run();
 if(Number(write.meta.changes)!==1)return Response.json({error:'revision_conflict'},{status:409,headers:noStore});
 return Response.json({status:'saved',revision:p.revision,assessment:stored.assessment,result,economics},{status:201,headers:noStore});
 }catch(error){console.error('garden_review_failed',error);return Response.json({error:'review_unavailable'},{status:503,headers:noStore});}
}
