import assert from 'node:assert/strict';
import test from 'node:test';
import { editEvidenceSource, appendEvidenceSource, removeEvidenceSource, reviewInputIssues } from '../lib/garden-review-editor.ts';
const source=(reference)=>({reference,date:'2026-10-18',kind:'order',expiresAt:'2026-11-30'});
test('editing one evidence source preserves other sources and every source metadata field',()=>{
 const original={demand:{verified:true,conclusion:'Demand',sources:[source('one'),source('two')]}};
 const next=editEvidenceSource(original,'demand',0,{reference:'edited'});
 assert.deepEqual(next.demand.sources,[{...source('one'),reference:'edited'},source('two')]);
 assert.equal(next.demand.verified,false);assert.equal(original.demand.sources[0].reference,'one');
});
test('source add/remove supports 20 sources and never removes an unrelated source',()=>{
 let dims={demand:{verified:true,conclusion:'Demand',sources:[source('one'),source('two')]}};
 dims=removeEvidenceSource(dims,'demand',0);assert.deepEqual(dims.demand.sources,[source('two')]);
 for(let n=1;n<20;n++)dims=appendEvidenceSource(dims,'demand');
 assert.equal(dims.demand.sources.length,20);assert.throws(()=>appendEvidenceSource(dims,'demand'),RangeError);
});
test('market review form discloses missing evidence without requiring economics',()=>{
 const dimensions=Object.fromEntries(['demand','competition','differentiation','risk'].map(k=>[k,{verified:true,conclusion:k,sources:[source(k)]}]));
 const draft={status:'worth_validating',dimensions,confirmed:true,salesBlocked:false,reason:'',rejectionBasis:'market',asOf:'2026-10-19'};
 assert.deepEqual(reviewInputIssues(draft),[]);
 assert.ok(reviewInputIssues({...draft,confirmed:false}).some(x=>x.includes('人工确认')));
 assert.ok(reviewInputIssues({...draft,dimensions:{...dimensions,demand:{...dimensions.demand,sources:[]}}}).some(x=>x.includes('需求')));
 assert.deepEqual(reviewInputIssues({...draft,status:'pending_verification',dimensions:{},confirmed:false}),[]);
});

test('review form flags expired and future evidence using Pacific review date without changing server gates',()=>{
 const dimensions=Object.fromEntries(['demand','competition','differentiation','risk'].map(k=>[k,{verified:true,conclusion:k,sources:[source(k)]}]));
 const draft={status:'worth_validating',dimensions,confirmed:true,salesBlocked:false,reason:'',rejectionBasis:'market',asOf:'2026-10-19'};
 assert.deepEqual(reviewInputIssues(draft),[]);
 assert.ok(reviewInputIssues({...draft,asOf:'2026-12-01'}).some(x=>x.includes('需求')));
 assert.ok(reviewInputIssues({...draft,asOf:'2026-10-01'}).some(x=>x.includes('需求')));
});
