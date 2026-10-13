import test from 'node:test';import assert from 'node:assert/strict';
import { validateGardenReview } from '../lib/garden-review-contract.ts';
test('rejects malformed payload and client-computed profits',()=>{assert.equal(validateGardenReview(null).ok,false);assert.equal(validateGardenReview({economics:{netProfit:'999'}}).ok,false);});
test('rejects invalid revisions before persistence',()=>{assert.equal(validateGardenReview({marketplace:'AMAZON_US',asin:'B000000001',categoryKey:'patio_lawn_garden',revision:2,previousRevision:0,published:true,assessment:{},economicsInput:{}}).ok,false);});
