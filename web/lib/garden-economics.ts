/** All arithmetic uses rational BigInts; only displayed results are rounded. */
export const GARDEN_COST_CATEGORIES = ['procurement','packaging','freight','duty','commission','fulfillment','storage','advertising','discount','returns','other'] as const;
export type GardenCostCategory = typeof GARDEN_COST_CATEGORIES[number];
export type EconomicSource = { reference: string; date: string; expiresAt?: string; kind: 'invoice'|'settlement'|'order'|'quote'|'official_fee'|'assumption'|'exchange_rate'; };
export type EconomicInput = { amount: string|null; status:'verified'|'assumption'|'missing'|'not_applicable'; source?:EconomicSource; currency:string; unit:string; specification:string; conditions:string; quantity?:string; notApplicableReason?:string; fx?:{rate:string;source:EconomicSource}; };
export type EconomicCost = EconomicInput & { category:GardenCostCategory; basis:'per_unit'|'batch'|'percent_revenue'; includes?:GardenCostCategory[] };
export type GardenEconomicsInput = { mode:'forecast'|'actual'; currency:string; asOf:string; revision:number; salePrice:EconomicInput; costs:EconomicCost[]; scenarios?:{label:string;salePrice:string;advertising?:string;returns?:string}[] };
type Rational = {n:bigint;d:bigint};
const ZERO=BigInt(0), ONE=BigInt(1), HUNDRED=BigInt(100);
function decimal(value:string):Rational { if(!/^\d+(?:\.\d{1,12})?$/.test(value))throw new Error('金额必须是非负十进制字符串');const [a,b='']=value.split('.');return {n:BigInt(a+b),d:BigInt(10)**BigInt(b.length)}; }
const add=(a:Rational,b:Rational):Rational=>({n:a.n*b.d+b.n*a.d,d:a.d*b.d});
const mul=(a:Rational,b:Rational):Rational=>({n:a.n*b.n,d:a.d*b.d});
const div=(a:Rational,b:Rational):Rational=>{if(b.n===ZERO)throw new Error('除数不能为零');return {n:a.n*b.d,d:a.d*b.n};};
const sub=(a:Rational,b:Rational):Rational=>add(a,{n:-b.n,d:b.d});
const z=():Rational=>({n:ZERO,d:ONE});
function display(v:Rational):string{const negative=v.n<ZERO;const n=negative?-v.n:v.n;const rounded=(n*HUNDRED+v.d/BigInt(2))/v.d;return `${negative?'-':''}${rounded/HUNDRED}.${String(rounded%HUNDRED).padStart(2,'0')}`;}
function validDate(date:string):boolean {return /^\d{4}-\d{2}-\d{2}$/.test(date) && Number.isFinite(Date.parse(date)) && new Date(date).toISOString().slice(0,10)===date;}
export function economicSourceValid(source:EconomicSource|undefined,asOf:string):boolean {return !!source && typeof source.reference==='string' && !!source.reference.trim() && validDate(asOf) && validDate(source.date) && source.date<=asOf && (!source.expiresAt || (validDate(source.expiresAt) && source.expiresAt>=asOf && source.expiresAt>=source.date));}
export function calculateGardenEconomics(input:GardenEconomicsInput) {
 const issues:string[]=[];let assumptions=false;let fixed=z(), rate=z(), price=z();
 input=input??({} as GardenEconomicsInput);
 if(!['actual','forecast'].includes(input.mode)||!validDate(input.asOf??'')||!Number.isSafeInteger(input.revision)||input.revision<1||!/^[A-Z]{3}$/.test(input.currency??''))issues.push('核算模式、日期、版本或币种无效');
 const costs=Array.isArray(input.costs)?input.costs:[];if(!Array.isArray(input.costs))issues.push('成本清单缺失');
 function read(item:EconomicInput,label:string,basis='per_unit'):Rational {
  if(!item || !['verified','assumption','missing','not_applicable'].includes(item.status))throw new Error(`${label}状态无效`);
  if(!['per_unit','batch','percent_revenue'].includes(basis))throw new Error(`${label}计价方式无效`);
  if(item.status==='missing')throw new Error(`${label}缺失`);
  if(!economicSourceValid(item.source,input.asOf))throw new Error(`${label}来源缺失或失效`);
  if(!item.unit?.trim()||!item.specification?.trim()||!item.conditions?.trim())throw new Error(`${label}适用条件不完整`);
  if(item.status==='assumption'){assumptions=true;if(input.mode==='actual')throw new Error(`${label}实际核算不能使用假设`);}
  if(input.mode==='actual' && item.status==='verified' && !['invoice','settlement','order'].includes(item.source!.kind))throw new Error(`${label}实际核算需要实际凭证`);
  if(item.status==='verified' && item.source!.kind==='assumption')throw new Error(`${label}假设不能标为已核实`);
  if(item.status==='not_applicable'){if(!item.notApplicableReason?.trim())throw new Error(`${label}不适用原因缺失`);if(item.amount!==null&&item.amount!=='0')throw new Error(`${label}不适用费用不能有金额`);return z();}
  if(item.amount===null)throw new Error(`${label}金额缺失`);
  let amount=decimal(item.amount);
  if(basis==='percent_revenue'){if(item.currency!==input.currency||item.unit!=='percent')throw new Error(`${label}比例费用必须使用核算币种及percent单位`);if(amount.n>HUNDRED*amount.d)throw new Error(`${label}比例超出100%`);return div(amount,{n:HUNDRED,d:ONE});}
  if(item.currency!==input.currency){if(!item.fx||item.fx.source?.kind!=='exchange_rate'||!economicSourceValid(item.fx.source,input.asOf))throw new Error(`${label}汇率缺失或失效`);const fx=decimal(item.fx.rate);if(fx.n===ZERO)throw new Error(`${label}汇率不能为零`);amount=mul(amount,fx);}
  if(basis==='batch'){if(!item.quantity || !/^[1-9]\d*$/.test(item.quantity))throw new Error(`${label}批量数量必须是正整数`);amount=div(amount,decimal(item.quantity));}
  return amount;
 }
 try{price=read(input.salePrice,'售价');if(price.n===ZERO)issues.push('售价必须大于零');}catch(e){issues.push((e as Error).message);}
 const seen=new Set<string>();const values=new Map<string,Rational>();
 for(const item of costs){if(!item||!GARDEN_COST_CATEGORIES.includes(item.category)){issues.push('未知成本类别');continue;}if(seen.has(item.category))issues.push(`${item.category}重复计费`);seen.add(item.category);try{const amount=read(item,item.category,item.basis);values.set(item.category,amount);if(item.basis==='percent_revenue')rate=add(rate,amount);else fixed=add(fixed,amount);}catch(e){issues.push((e as Error).message);}}
 for(const category of GARDEN_COST_CATEGORIES)if(!seen.has(category))issues.push(`${category}缺失`);
 for(const item of costs.filter(Boolean))for(const included of Array.isArray(item.includes)?item.includes:[]){const charge=costs.find(c=>c.category===included);if(included===item.category||!charge||charge.status!=='not_applicable')issues.push(`${item.category}包含${included}，需明确排除重复费用`);}
 if(rate.n>=rate.d)issues.push('收入比例费用合计必须小于100%');
 const complete=issues.length===0;
 function result(p:Rational,f:Rational,r=rate){const cost=add(f,mul(p,r)),profit=sub(p,cost);return {totalCost:display(cost),netProfit:display(profit),netMarginPercent:display(mul(div(profit,p),{n:HUNDRED,d:ONE})),breakEvenPrice:display(div(f,sub({n:ONE,d:ONE},r)))};}
 const amounts=complete?result(price,fixed):{totalCost:null,netProfit:null,netMarginPercent:null,breakEvenPrice:null};
 const sensitivities:({label:string;netProfit:string|null;issue?:string})[]=[];
 if(complete)for(const s of Array.isArray(input.scenarios)?input.scenarios:[]){try{let f=fixed,r=rate;for(const category of ['advertising','returns'] as const)if(s[category]!==undefined){if(costs.find(c=>c.category===category)?.basis==='percent_revenue'){const replacement=div(decimal(s[category]!),{n:HUNDRED,d:ONE});if(replacement.n>replacement.d)throw new Error('情景比例超出100%');r=add(sub(r,values.get(category)!),replacement);}else f=add(sub(f,values.get(category)!),decimal(s[category]!));}if(r.n>=r.d)throw new Error('情景收入比例费用必须小于100%');const p=decimal(s.salePrice);if(p.n===ZERO)throw new Error('情景售价必须大于零');sensitivities.push({label:s.label,netProfit:result(p,f,r).netProfit});}catch(e){sensitivities.push({label:s.label,netProfit:null,issue:(e as Error).message});}}
 return {mode:input.mode,revision:input.revision,complete,verified:complete&&!assumptions,hasAssumptions:assumptions,issues,...amounts,sensitivities};
}
export type GardenEconomicsResult = ReturnType<typeof calculateGardenEconomics>;
