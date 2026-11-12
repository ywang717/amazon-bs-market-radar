import assert from 'node:assert/strict';
import { register } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const workerEnvironment=globalThis.__dashboardWorkerEnvironment??={};
const root=new URL('../',import.meta.url).href;
register(`data:text/javascript,const root=${JSON.stringify(root)};export async function resolve(s,c,n){if(s==='cloudflare:workers')return {url:'data:text/javascript,export const env=globalThis.__dashboardWorkerEnvironment',shortCircuit:true};if(s.startsWith('@/'))return {url:new URL(s.slice(2)+(/\\.[a-z]+$/i.test(s)?'':'.ts'),root).href,shortCircuit:true};return n(s,c);}`,import.meta.url);
const {GET}=await import('../app/api/public/garden-opportunities/route.ts');
const {ensureSchema}=await import('../lib/d1.ts');

async function setup(){
 const sqlite=new DatabaseSync(':memory:');
 function prepare(sql){let values=[];return {bind(...bound){values=bound;return this;},async first(){return sqlite.prepare(sql).get(...values)??null;},async all(){return {results:sqlite.prepare(sql).all(...values)};},async run(){return {meta:{changes:Number(sqlite.prepare(sql).run(...values).changes)}};}};}
 const DB={prepare,async batch(statements){for(const statement of statements)await statement.run();return [];}};
 for(const key of Reflect.ownKeys(workerEnvironment))delete workerEnvironment[key];
 Object.assign(workerEnvironment,{DB});
 await ensureSchema(DB);
}

test('Garden opportunity API exposes a machine-readable empty result and rejects unknown categories',async()=>{
 await setup();
 const invalid=await GET(new Request('http://localhost/api/public/garden-opportunities?categoryKey=unknown'));
 assert.equal(invalid.status,400);
 const valid=await GET(new Request('http://localhost/api/public/garden-opportunities?categoryKey=garden_power_tools'));
 assert.equal(valid.status,200);
 const payload=await valid.json();
 assert.equal(payload.scope,'garden_opportunities');
 assert.equal(payload.count,0);
 assert.equal(payload.filters.categoryKey,'garden_power_tools');
});
