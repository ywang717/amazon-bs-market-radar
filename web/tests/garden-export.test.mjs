import assert from 'node:assert/strict';
import test from 'node:test';
import { buildGardenOpportunityCsv, buildGardenOpportunityJson } from '../lib/garden-export.ts';

const product={
 asin:'B000000001',title:'=Potential Tool',url:'https://www.amazon.com/dp/B000000001',price:19.99,rating:4.5,reviews:null,rank:3,rankChange:12,reviewGrowth:null,priceChange:null,history:[],signals:['排名快速提升'],discoverySignals:['新形态词首次进入：无线'],marketGap:{rankTopPercent:10,reviewBelowPercent:null,crossCategoryCount:2},confidence:60,candidate:true,brand:null,score:72,
 category:{key:'garden_power_tools',label:'工具',sourceUrl:'https://www.amazon.com/example',enabled:true,marketDate:'2026-10-26',completeMarketDays:7,latestComplete:true,products:[]}
};

test('Garden opportunity CSV preserves missing values and protects formula cells',()=>{
 const csv=buildGardenOpportunityCsv([product], '2026-11-12T00:00:00Z');
 assert.match(csv,/^\uFEFF/);
 assert.match(csv,/asin,title,category_key/);
 assert.match(csv,/'=Potential Tool/);
 assert.match(csv,/B000000001/);
 assert.match(csv,/garden_power_tools/);
 assert.match(csv,/review_below_percent/);
});

test('Garden opportunity JSON keeps evidence and source context machine-readable',()=>{
 const payload=JSON.parse(buildGardenOpportunityJson([product], {marketDate:'2026-10-26',updatedAt:'2026-10-26T17:00:03Z'}));
 assert.equal(payload.marketDate,'2026-10-26');
 assert.equal(payload.count,1);
 assert.equal(payload.products[0].reviews,null);
 assert.deepEqual(payload.products[0].discoverySignals,['新形态词首次进入：无线']);
 assert.equal(payload.products[0].marketGap.crossCategoryCount,2);
});
