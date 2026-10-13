"use client";
import type { EconomicInput, EconomicCost, GardenEconomicsInput } from '@/lib/garden-economics';
const names:Record<string,string>={procurement:'采购',packaging:'包装',freight:'头程运输',duty:'关税',commission:'平台佣金',fulfillment:'履约',storage:'仓储',advertising:'广告',discount:'优惠',returns:'退货损失',other:'其他适用费用'};
function AmountFields({label,value,onChange,cost=false}:{label:string;value:EconomicInput|EconomicCost;onChange:(v:EconomicInput|EconomicCost)=>void;cost?:boolean}){
 const update=(key:string,v:unknown)=>onChange({...value,[key]:v});const source=value.source;
 const setSource=(key:string,v:string)=>update('source',{reference:'',date:'',kind:'quote',...source,[key]:v});
 return <details className="gardenCost" open={value.status==='missing'}><summary>{label} · {value.status==='missing'?'缺失':value.status==='assumption'?'假设':value.status==='not_applicable'?'不适用':'已核验'} · {value.amount??'—'} {value.currency}</summary><div className="gardenFilters">
 <label>金额／比例<input type="text" inputMode="decimal" value={value.amount??''} onChange={e=>update('amount',e.target.value||null)}/></label>
 <label>证据状态<select value={value.status} onChange={e=>update('status',e.target.value)}><option value="missing">缺失</option><option value="assumption">预测假设</option><option value="verified">来源及适用条件已核验</option>{cost&&<option value="not_applicable">不适用（需说明）</option>}</select></label>
 {cost&&<label>计价方式<select value={(value as EconomicCost).basis} onChange={e=>onChange({...value,basis:e.target.value,unit:e.target.value==='percent_revenue'?'percent':'per unit'} as EconomicCost)}><option value="per_unit">每件金额</option><option value="batch">整批金额</option><option value="percent_revenue">占成交收入比例（%）</option></select></label>}
 <label>币种<input value={value.currency} maxLength={3} onChange={e=>update('currency',e.target.value.toUpperCase())}/></label>
 <label>计价单位<input value={value.unit} onChange={e=>update('unit',e.target.value)}/></label>
 {cost&&(value as EconomicCost).basis==='batch'&&<label>批量件数（MOQ）<input inputMode="numeric" value={value.quantity??''} onChange={e=>update('quantity',e.target.value)}/></label>}
 <label>产品规格／SKU<input value={value.specification} onChange={e=>update('specification',e.target.value)}/></label>
 <label>适用条件、贸易条款及运输方式<input value={value.conditions} onChange={e=>update('conditions',e.target.value)}/></label>
 <label>来源引用／凭证编号<input value={source?.reference??''} onChange={e=>setSource('reference',e.target.value)}/></label>
 <label>来源类型<select value={source?.kind??'quote'} onChange={e=>setSource('kind',e.target.value)}><option value="quote">供应商／物流报价</option><option value="official_fee">官方费用工具</option><option value="invoice">账单／发票</option><option value="settlement">实际结算</option><option value="order">订单记录</option><option value="assumption">预测假设依据</option></select></label>
 <label>来源日期<input type="date" value={source?.date??''} onChange={e=>setSource('date',e.target.value)}/></label>
 <label>有效截止日<input type="date" value={source?.expiresAt??''} onChange={e=>setSource('expiresAt',e.target.value)}/></label>
 {value.status==='not_applicable'&&<label>不适用／已包含的依据<input value={value.notApplicableReason??''} onChange={e=>update('notApplicableReason',e.target.value)}/></label>}
 {value.currency!=='USD'&&<><label>换算为 USD 的汇率<input inputMode="decimal" value={value.fx?.rate??''} onChange={e=>update('fx',{rate:e.target.value,source:{reference:'',date:'',kind:'exchange_rate',...value.fx?.source}})}/></label><label>汇率来源<input value={value.fx?.source.reference??''} onChange={e=>update('fx',{rate:value.fx?.rate??'',source:{date:'',kind:'exchange_rate',...value.fx?.source,reference:e.target.value}})}/></label><label>汇率日期<input type="date" value={value.fx?.source.date??''} onChange={e=>update('fx',{rate:value.fx?.rate??'',source:{reference:'',kind:'exchange_rate',...value.fx?.source,date:e.target.value}})}/></label></>}
 {cost&&<label>此费用包含的其他成本（被包含项需标为不适用）<select multiple value={(value as EconomicCost).includes??[]} onChange={e=>update('includes',Array.from(e.target.selectedOptions).map(o=>o.value))}>{Object.entries(names).filter(([key])=>key!==(value as EconomicCost).category).map(([key,name])=><option key={key} value={key}>{name}</option>)}</select></label>}
 </div></details>;
}
export function EconomicsFields({text,onChange}:{text:string;onChange:(text:string)=>void}){
 let input:GardenEconomicsInput;try{input=JSON.parse(text);if(!input.salePrice||!Array.isArray(input.costs))throw new Error();}catch{return <p role="alert">核算明细格式无效，请修正高级明细或重新读取记录。</p>;}
 const update=(value:GardenEconomicsInput)=>onChange(JSON.stringify(value,null,2));
 return <><div className="gardenFilters"><label>核算口径<select value={input.mode} onChange={e=>update({...input,mode:e.target.value as GardenEconomicsInput['mode']})}><option value="forecast">新品预测</option><option value="actual">实际经营</option></select></label><label>核算日期（太平洋时间）<input type="date" value={input.asOf} onChange={e=>update({...input,asOf:e.target.value})}/></label></div><AmountFields label="实际／预期成交售价" value={input.salePrice} onChange={v=>update({...input,salePrice:v})}/>{input.costs.map((cost,index)=><AmountFields key={cost.category} label={names[cost.category]??cost.category} value={cost} cost onChange={v=>update({...input,costs:input.costs.map((c,i)=>i===index?v as EconomicCost:c)})}/>)}<p>售价为优惠前的成交收入基准；如已使用优惠后的净售价，优惠项必须说明已包含，避免重复扣减。汇率按 1 单位来源币种可兑换的 USD 填写。</p></>;
}
