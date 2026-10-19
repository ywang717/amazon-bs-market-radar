import test from 'node:test';
import assert from 'node:assert/strict';
import { selectGardenProducts, gardenEmptyReason } from '../lib/garden-browser.ts';
const product=(asin,rank,candidate=true)=>({asin,rank,candidate,title:asin,signals:['高排名低评论'],price:20,confidence:60,score:50,history:[]});
const categories=[{key:'garden_a',label:'A',completeMarketDays:7,products:[product('B000000001',2),product('B000000002',1)]},{key:'garden_b',label:'B',completeMarketDays:7,products:[product('B000000001',1)]}];
test('Garden filtering sorts and deduplicates before pagination without promoting non-candidates',()=>{
 assert.deepEqual(selectGardenProducts(categories,{},true).map(p=>p.asin),['B000000002','B000000001']);
 assert.deepEqual(selectGardenProducts(categories,{categoryKey:'garden_a',q:'000002'},true).map(p=>p.asin),['B000000002']);
 assert.deepEqual(selectGardenProducts([{...categories[0],completeMarketDays:6}],{},true),[]);
 assert.deepEqual(selectGardenProducts([{...categories[0],products:[product('B000000003',1,false)]}],{},true),[]);
});
test('Garden empty states distinguish service failure, insufficient history, thresholds and active filters',()=>{
 assert.equal(gardenEmptyReason(categories,true,true,0,0),'error');
 assert.equal(gardenEmptyReason([{...categories[0],completeMarketDays:6}],true,false,0,0),'insufficient');
 assert.equal(gardenEmptyReason(categories,true,false,0,0),'threshold');
 assert.equal(gardenEmptyReason(categories,true,false,2,0),'filtered');
});

test('published review reader rejects malformed dimensions rather than crashing the page or showing empty',async()=>{
 const {readPublishedReviews}=await import('../lib/garden-browser.ts');assert.equal(typeof readPublishedReviews,'function');
 const row={asin:'B000000001',categoryKey:'patio_lawn_garden',status:'pending_verification',updatedAt:'2026-10-18T20:00:00Z',issues:[],dimensions:{demand:{verified:false,conclusion:'Needs review',sourceCount:2}}};
 assert.deepEqual(readPublishedReviews({reviews:[row]}),[row]);assert.deepEqual(readPublishedReviews({reviews:[]}),[]);
 for(const bad of [{},{reviews:[{...row,dimensions:{demand:null}}]},{reviews:[{...row,issues:'invalid'}]},{reviews:[{...row,status:'guaranteed_sales'}]}])assert.throws(()=>readPublishedReviews(bad));
});

test('signal choices retain every eligible membership before ASIN deduplication',async()=>{
 const {gardenSignalOptions}=await import('../lib/garden-browser.ts');
 const shared=[{...categories[0],products:[{...product('B000000001',1),signals:['A']}]},{...categories[1],products:[{...product('B000000001',2),signals:['B']}]}];
 assert.deepEqual(gardenSignalOptions(shared,'',true),['A','B']);
 assert.deepEqual(gardenSignalOptions(shared,'garden_a',true),['A']);
 assert.equal(selectGardenProducts(shared,{signal:'B'},true)[0].category.key,'garden_b');
 assert.deepEqual(gardenSignalOptions([{...shared[0],completeMarketDays:6}], '',true),[]);
});
