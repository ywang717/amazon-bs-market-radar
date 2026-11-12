import test from 'node:test';
import assert from 'node:assert/strict';
import { buildGardenData } from '../lib/garden-data.ts';
const categories=[{categoryKey:'garden_test',labelZh:'测试分支',sourceUrl:'https://www.amazon.com/zgbs/lawn-garden/1',enabled:true}];
const rows=(date)=>Array.from({length:30},(_,i)=>({market_date:date,category_key:'garden_test',rank:i+1,asin:`B${String(i).padStart(9,'0')}`,title:'Product',url:'https://www.amazon.com/dp/B000000000',price:20,rating:4.5,reviews:100}));
function fixture(n){const dates=Array.from({length:n},(_,i)=>`2026-10-${String(i+1).padStart(2,'0')}`);return {categories,categoryDays:dates.map(market_date=>({market_date,category_key:'garden_test',complete:1})),observations:dates.flatMap(rows),metadata:[],latestMarketDate:dates.at(-1)};}
test('Garden registry exposes the monitored Garden Hoses branch to Garden pages',async()=>{const {gardenRegistryCategories}=await import('../lib/garden-data.ts');const gardenHoses=gardenRegistryCategories().find(c=>c.categoryKey==='garden_hoses');assert.deepEqual(gardenHoses&&{categoryKey:gardenHoses.categoryKey,labelZh:gardenHoses.labelZh,sourceUrl:gardenHoses.sourceUrl}, {categoryKey:'garden_hoses',labelZh:'花园软管',sourceUrl:'https://www.amazon.com/Best-Sellers-Garden-Hoses/zgbs/lawn-garden/553966'});});
test('baseline never becomes opportunity',()=>{const data=buildGardenData(fixture(1));assert.equal(data.categories[0].completeMarketDays,1);assert.equal(data.categories[0].products.some(p=>p.candidate),false);});
test('failed latest capture retains last valid category date and marks stale',()=>{const f=fixture(7);f.latestMarketDate='2026-10-08';f.categoryDays.push({market_date:'2026-10-08',category_key:'garden_test',complete:0});f.observations.push(...rows('2026-10-08').slice(0,8));const c=buildGardenData(f).categories[0];assert.equal(c.marketDate,'2026-10-07');assert.equal(c.latestComplete,false);assert.equal(c.products.length,30);});
test('rank continuity and unique ASINs are revalidated',()=>{const f=fixture(7);f.observations=f.observations.filter(r=>!(r.market_date==='2026-10-07'&&r.rank===30));assert.equal(buildGardenData(f).categories[0].completeMarketDays,6);});
test('confidence penalizes missing fields and short product observation history',()=>{const f=fixture(7);for(const r of f.observations){r.rating=null;r.reviews=null;}const p=buildGardenData(f).categories[0].products[0];assert.ok(p.confidence<50);assert.equal(p.candidate,false);});
test('a complete seven-day rising product qualifies with evidence',()=>{const f=fixture(7);for(const r of f.observations){const day=Number(r.market_date.slice(-2));if(r.asin==='B000000000'){r.rank=day===7?1:30;r.reviews=100+day*20;}else if(r.asin==='B000000029'){r.rank=day===7?30:1;}}const p=buildGardenData(f).categories[0].products.find(p=>p.asin==='B000000000');assert.equal(p.candidate,true);assert.ok(p.signals.includes('短期大幅波动，需核查促销'));});

test('discovery evidence identifies new form terms and relative low-review gaps without changing gates',()=>{
 const f=fixture(7);const current=f.observations.filter(r=>r.market_date==='2026-10-07');
 current[0].title='Portable Wall Mounted Garden Hose';current[0].rank=1;current[0].reviews=10;
 current[1].title='Portable Wall Mounted Garden Hose';current[1].rank=2;current[1].reviews=20;
 const product=buildGardenData(f).categories[0].products.find(p=>p.asin==='B000000000');
 assert.ok(product.discoverySignals.some(signal=>signal.includes('新形态')));
 assert.ok(product.marketGap.rankTopPercent<=10);
 assert.ok(product.marketGap.reviewBelowPercent>=90);
 assert.equal(product.candidate,false);
});

test('discovery evidence keeps missing review values as null',()=>{
 const f=fixture(7);const current=f.observations.find(r=>r.market_date==='2026-10-07'&&r.asin==='B000000000');current.reviews=null;
 const product=buildGardenData(f).categories[0].products.find(p=>p.asin==='B000000000');
 assert.equal(product.marketGap.reviewBelowPercent,null);
});

test('discovery evidence counts cross-category appearances without changing the product identity',()=>{
 const second={categoryKey:'garden_second',labelZh:'第二榜单',sourceUrl:'https://www.amazon.com/zgbs/lawn-garden/2',enabled:true};
 const f=fixture(7);const dates=f.categoryDays.map(row=>({...row,category_key:'garden_second'}));
 const secondRows=f.observations.map(row=>({...row,category_key:'garden_second'}));
 f.categories=[categories[0],second];f.categoryDays=[...f.categoryDays,...dates];f.observations=[...f.observations,...secondRows];
 const product=buildGardenData(f).categories[0].products.find(p=>p.asin==='B000000000');
 assert.equal(product.marketGap.crossCategoryCount,2);
 assert.ok(product.discoverySignals.some(signal=>signal.includes('跨 Garden 榜单')));
});

test('automatic candidate gate preserves seven days, confidence50, score45 and a real signal',async()=>{
 const {meetsGardenCandidateThresholds}=await import('../lib/garden-data.ts');
 assert.equal(typeof meetsGardenCandidateThresholds,'function');
 assert.equal(meetsGardenCandidateThresholds(7,50,45,1),true);
 for(const row of [[6,50,45,1],[7,49,45,1],[7,50,44,1],[7,50,null,1],[7,50,45,0]])assert.equal(meetsGardenCandidateThresholds(...row),false);
});
