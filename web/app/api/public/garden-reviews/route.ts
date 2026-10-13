import { calculateGardenEconomics } from '@/lib/garden-economics';
import { evaluateGardenOpportunity } from '@/lib/garden-opportunity';
import { getD1,ensureSchema } from '@/lib/d1';
export async function GET(request:Request){
 const query=new URL(request.url).searchParams;const asin=query.get('asin'),category=query.get('categoryKey');
 if((asin&&!/^B[A-Z0-9]{9}$/.test(asin))||(category&&!/^\w{1,80}$/.test(category)))return Response.json({error:'invalid_scope'},{status:400});
 try{const db=getD1();await ensureSchema(db);const clauses=["r.marketplace='AMAZON_US'",'r.published=1','r.revision=(SELECT MAX(v.revision) FROM garden_review_versions v WHERE v.marketplace=r.marketplace AND v.asin=r.asin AND v.category_key=r.category_key)'];const values:string[]=[];if(asin){clauses.push('r.asin=?');values.push(asin);}if(category){clauses.push('r.category_key=?');values.push(category);}const rows=await db.prepare(`SELECT public_json,content_json FROM garden_review_versions r WHERE ${clauses.join(' AND ')} ORDER BY updated_at DESC LIMIT 100`).bind(...values).all<{public_json:string;content_json:string}>();return Response.json({reviews:rows.results.map(r=>{
 const pub=JSON.parse(r.public_json),record=JSON.parse(r.content_json);
 const today=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Los_Angeles',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const economics=calculateGardenEconomics({...record.economicsInput,asOf:today});
 const assessment={...record.assessment,asOf:today,economics};
 const result=evaluateGardenOpportunity(assessment);
 return {...pub,status:result.status,issues:result.issues,economics:{mode:economics.mode,currency:record.economicsInput.currency,complete:economics.complete,verified:economics.verified,hasAssumptions:economics.hasAssumptions,issues:economics.issues,...(economics.complete?{netProfit:economics.netProfit,netMarginPercent:economics.netMarginPercent,breakEvenPrice:economics.breakEvenPrice}:{})}};
 })},{headers:{'cache-control':'no-store'}});}catch{return Response.json({error:'review_unavailable'},{status:503});}
}
