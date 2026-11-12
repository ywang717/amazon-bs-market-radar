import { loadGardenData } from '@/lib/garden-data';
import { selectGardenProducts } from '@/lib/garden-browser';

function numericFilter(value:string|null){
 if(value===null||value==='')return null;
 const number=Number(value);return Number.isFinite(number)&&number>=0?value:null;
}

export async function GET(request:Request){
 const query=new URL(request.url).searchParams;
 const data=await loadGardenData();
 if(data.error)return Response.json({error:data.error,latestMarketDate:data.latestMarketDate,updatedAt:data.updatedAt},{status:503,headers:{'cache-control':'no-store'}});
 const categoryKey=query.get('categoryKey')??'';
 if(categoryKey&&!data.categories.some(category=>category.key===categoryKey))return Response.json({error:'invalid_category'},{status:400});
 const minPrice=numericFilter(query.get('minPrice')),maxPrice=numericFilter(query.get('maxPrice'));
 if((query.has('minPrice')&&minPrice===null)||(query.has('maxPrice')&&maxPrice===null)||(minPrice&&maxPrice&&Number(minPrice)>Number(maxPrice)))return Response.json({error:'invalid_price_range'},{status:400});
 const filters={categoryKey:categoryKey||undefined,q:query.get('q')??undefined,signal:query.get('signal')??undefined,discovery:query.get('discovery')??undefined,minPrice:minPrice??undefined,maxPrice:maxPrice??undefined,sort:query.get('sort')??'score'};
 const products=selectGardenProducts(data.categories,filters,true).map(({category,...product})=>({...product,category:{key:category.key,label:category.label,marketDate:category.marketDate,completeMarketDays:category.completeMarketDays,latestComplete:category.latestComplete}}));
 return Response.json({scope:'garden_opportunities',latestMarketDate:data.latestMarketDate,updatedAt:data.updatedAt,count:products.length,filters,products},{headers:{'cache-control':'no-store'}});
}
