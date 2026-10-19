"""Read-only snapshot/Postgres/production-rank reconciliation; credentials never logged."""
import argparse,asyncio,hashlib,json,os,subprocess
from pathlib import Path
from urllib.request import getproxies
from playwright.async_api import async_playwright
p=argparse.ArgumentParser();p.add_argument('--output',required=True);p.add_argument('--base',default='https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site');a=p.parse_args();root=Path(__file__).resolve().parents[2];out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
async def main():
 config=json.loads((root/'.local/postgres-settings.json').read_text(encoding='utf-8-sig'));env=dict(os.environ,PGPASSWORD=config['password'],LANG='C',LC_ALL='C')
 sql='SET search_path TO amazon_intelligence,public; SELECT r.market_date,r.artifact_sha256,count(*) FROM best_sellers_observation o JOIN best_sellers_run r ON r.best_sellers_run_id=o.best_sellers_run_id GROUP BY r.market_date,r.artifact_sha256;'
 result=subprocess.run([str(Path(config['install_root'])/'bin/psql.exe'),'-qAt','-h',config['host'],'-p',str(config['port']),'-U',config['username'],'-d',config['database'],'-c',sql],env=env,text=True,capture_output=True)
 if result.returncode:raise RuntimeError('Read-only PostgreSQL reconciliation query failed')
 pg={(parts[0],parts[1]):int(parts[2]) for line in result.stdout.splitlines() if len(parts:=line.split('|'))==3}
 rows=[];api_jobs=[]
 for receipt in sorted((root/'var/amazon-bestsellers').glob('2026-*/best-sellers-capture-receipt.json')):
  data=json.loads(receipt.read_text(encoding='utf-8-sig'));snapshot=receipt.parent/'amazon-bestsellers.json'
  if not snapshot.exists():continue
  sha=hashlib.sha256(snapshot.read_bytes()).hexdigest();snap=json.loads(snapshot.read_text(encoding='utf-8-sig'));date=receipt.parent.name;count=sum(len(v) for v in snap.values() if isinstance(v,list))
  item={'date':date,'receipt_status':data.get('status'),'snapshot_sha':sha,'receipt_matches':sha==data.get('snapshot_sha256'),'snapshot_count':count,'postgres_count':pg.get((date,sha))};rows.append(item)
  if data.get('status')=='COMPLETE_VALIDATED' and item['receipt_matches']:
   for key,values in snap.items():
    if isinstance(values,list) and len(values)==30:api_jobs.append((date,key,[(int(v['rank']),v['asin']) for v in values]))
 checks=[]
 async with async_playwright() as pw:
  browser=await pw.chromium.launch(headless=True,proxy={'server':getproxies()['https']});ctx=await browser.new_context();page=await ctx.new_page();await page.goto(a.base+'/garden',wait_until='networkidle',timeout=45000)
  for offset in range(0,len(api_jobs),3):
   jobs=api_jobs[offset:offset+3]
   responses=await page.evaluate('''async jobs=>Promise.all(jobs.map(async ([date,key])=>{try{const r=await fetch('/api/public/rankings?date='+date+'&category='+key+'&segment=all');const body=await r.json();return {status:r.status,rows:(body.observations||[]).map(v=>[v.rank,v.asin])}}catch{return {status:0,rows:[]}}}))''',jobs)
   for (date,key,expected),actual in zip(jobs,responses):checks.append({'date':date,'category':key,'status':actual['status'],'matches':actual['status']==200 and sorted(actual['rows'])==sorted([list(v) for v in expected])})
  await browser.close()
 report={'snapshots':rows,'website_checks':checks,'summary':{'snapshots':len(rows),'hash_mismatch':sum(not r['receipt_matches'] for r in rows),'postgres_mismatch':[r['date'] for r in rows if r['receipt_status']=='COMPLETE_VALIDATED' and r['postgres_count']!=r['snapshot_count']],'website_queries':len(checks),'website_mismatch':[r for r in checks if not r['matches']]}}
 (out/'data-reconciliation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report['summary'],ensure_ascii=False),flush=True)
asyncio.run(main())
