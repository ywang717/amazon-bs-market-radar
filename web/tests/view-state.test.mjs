import assert from 'node:assert/strict';
import test from 'node:test';
import { patchViewQuery, pageRows } from '../lib/view-state.ts';

test('changing a filter preserves market context and resets pagination', () => {
 assert.equal(patchViewQuery('category=pressure_washers&date=2026-10-15&segment=all&q=old&page=3', {q:'Westinghouse',page:null}), 'category=pressure_washers&date=2026-10-15&segment=all&q=Westinghouse');
 assert.equal(patchViewQuery('category=pressure_washers&date=2026-10-15&segment=all&q=x&filter=up', {q:null,filter:null}), 'category=pressure_washers&date=2026-10-15&segment=all');
});
test('pagination clamps malformed and out-of-range pages without losing records', () => {
 const rows=Array.from({length:43},(_,i)=>i+1);
 assert.deepEqual(pageRows(rows,'3',20),{rows:[41,42,43],page:3,pages:3,total:43});
 assert.deepEqual(pageRows(rows,'999',20).rows,[41,42,43]);
 for(const page of ['0','-1','1.5','NaN','9007199254740999'])assert.equal(pageRows(rows,page,20).page,1);
 assert.deepEqual(pageRows([], '8',30),{rows:[],page:1,pages:1,total:0});
});

test('product return paths restore list filters without accepting external redirects',async()=>{
 const { safeListReturn }=await import('../lib/view-state.ts');
 assert.equal(safeListReturn('/products?category=pressure_washers&q=B012345678','/products'),'/products?category=pressure_washers&q=B012345678');
 assert.equal(safeListReturn('/rankings?limit=10','/products'),'/rankings?limit=10');
 for(const bad of ['//evil.example/products','https://evil.example/products','/api/sync/v1/bundles','javascript:alert(1)'])assert.equal(safeListReturn(bad,'/products'),'/products');
});

test('home research returns preserve context with the same internal-only safety rules',async()=>{const {safeListReturn}=await import('../lib/view-state.ts');assert.equal(safeListReturn('/?date=2026-10-18&category=pressure_washers&segment=all','/products'),'/?date=2026-10-18&category=pressure_washers&segment=all');});
