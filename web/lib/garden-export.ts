import type { GardenCategory, GardenProduct } from './garden-data.ts';

export type GardenExportProduct = GardenProduct & {category:GardenCategory};
type GardenExportContext = {marketDate?:string|null;updatedAt?:string|null};

const HEADERS=[
 'asin','title','category_key','category_label','market_date','rank','rank_change','price','rating','reviews','review_growth','price_change','score','confidence','candidate','signals','discovery_signals','rank_top_percent','review_below_percent','cross_category_count','missing_evidence',
] as const;

function missingEvidence(product:GardenExportProduct){
 const missing=[];
 if(product.price===null)missing.push('价格');
 if(product.rating===null)missing.push('评分');
 if(product.reviews===null)missing.push('评论数');
 if(product.rankChange===null)missing.push('可比较排名历史');
 return missing;
}

function exportRow(product:GardenExportProduct){
 return {
  asin:product.asin,title:product.title,category_key:product.category.key,category_label:product.category.label,market_date:product.category.marketDate,
  rank:product.rank,rank_change:product.rankChange,price:product.price,rating:product.rating,reviews:product.reviews,review_growth:product.reviewGrowth,price_change:product.priceChange,
  score:product.score,confidence:product.confidence,candidate:product.candidate,signals:product.signals.join(' | '),discovery_signals:product.discoverySignals.join(' | '),
  rank_top_percent:product.marketGap.rankTopPercent,review_below_percent:product.marketGap.reviewBelowPercent,cross_category_count:product.marketGap.crossCategoryCount,missing_evidence:missingEvidence(product).join(' | '),
 };
}

function exportJsonRow(product:GardenExportProduct){
 return {...exportRow(product),discoverySignals:product.discoverySignals,marketGap:product.marketGap,missingEvidence:missingEvidence(product)};
}

function csvCell(value:unknown){
 if(value===null||value===undefined)return '';
 let text=String(value);
 if(typeof value==='string'&&/^[=+\-@]/.test(text))text=`'${text}`;
 return `"${text.replaceAll('"','""')}"`;
}

export function buildGardenOpportunityCsv(products:readonly GardenExportProduct[], generatedAt=new Date().toISOString()){
 const rows=products.map(exportRow);
 const metadata=`# generated_at=${generatedAt}`;
 return `\uFEFF${metadata}\n${HEADERS.join(',')}\n${rows.map(row=>HEADERS.map(header=>csvCell(row[header])).join(',')).join('\n')}\n`;
}

export function buildGardenOpportunityJson(products:readonly GardenExportProduct[], context:GardenExportContext={}){
 return JSON.stringify({
  generatedAt:new Date().toISOString(),marketDate:context.marketDate??null,updatedAt:context.updatedAt??null,count:products.length,
  scope:'garden_opportunities',products:products.map(exportJsonRow),
 },null,2);
}

export function downloadGardenText(filename:string,content:string,mimeType:string){
 const blob=new Blob([content],{type:`${mimeType};charset=utf-8`});const url=URL.createObjectURL(blob);const anchor=document.createElement('a');anchor.href=url;anchor.download=filename;anchor.click();URL.revokeObjectURL(url);
}
