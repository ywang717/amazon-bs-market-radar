import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
const env=globalThis.__dashboardWorkerEnvironment??={};
register(`data:text/javascript,export async function resolve(s,c,n){if(s==='cloudflare:workers')return {url:'data:text/javascript,export const env=globalThis.__dashboardWorkerEnvironment',shortCircuit:true};return n(s,c);}`,import.meta.url);
const db={prepare(){return {bind(){return this;},async first(){return {date:null};},async all(){return {results:[]};},async run(){return {meta:{changes:0}};}};},async batch(){return [];}};
Object.assign(env,{DB:db,ASSETS:{fetch:async()=>new Response('Not found',{status:404})}});
const {default:worker}=await import('../dist/server/index.js');
test('garden navigation renders native top-frame links from reports and every secondary page',async()=>{
 for(const path of ['/reports?category=pressure_washers&segment=machines','/garden','/garden/products','/garden/opportunities']){
  const r=await worker.fetch(new Request('http://localhost'+path),env,{waitUntil(){},passThroughOnException(){}});assert.equal(r.status,200);const html=await r.text();
  const links=html.match(/<a\b[^>]*href="\/garden(?:\/products|\/opportunities)?"[^>]*>/g)??[];
  assert.ok(links.length>=1,path+' has garden entry');for(const link of links)assert.match(link,/target="_top"/,path+' navigation must work in an embedded Site');
 }
});

test('garden opportunities explains the research-to-verification path and empty-state meaning',async()=>{
 const r=await worker.fetch(new Request('http://localhost/garden/opportunities'),env,{waitUntil(){},passThroughOnException(){}});
 assert.equal(r.status,200);const html=await r.text();
 assert.match(html,/如何阅读商机/);
 assert.match(html,/自动初筛只发现研究线索/);
 assert.match(html,/人工核验/);
 assert.match(html,/完整市场日不足/);
});
