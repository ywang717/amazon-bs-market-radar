"""Seed only the explicitly selected temporary Wrangler database for browser QA."""
import datetime,json,sqlite3,sys
from pathlib import Path
root=Path(sys.argv[1]).resolve()
if not str(root).startswith('/tmp/amazon-bs-full-isolated') and not str(root).startswith('/private/tmp/amazon-bs-full-isolated'):raise SystemExit('Only isolated browser-audit storage is allowed')
paths=[p for p in root.rglob('*.sqlite') if p.name!='metadata.sqlite' and 'd1' in str(p)]
if len(paths)!=1:raise SystemExit('Expected one isolated D1 database; first request /api/health')
con=sqlite3.connect(paths[0]);con.execute('PRAGMA busy_timeout=5000');con.execute('DELETE FROM garden_review_versions')
registry=json.loads((Path(__file__).resolve().parents[1]/'config/category-registry.json').read_text())['categories']
dates=[f'2026-10-{day:02}' for day in range(12,19)]
for n,date in enumerate(dates):
 con.execute('INSERT OR REPLACE INTO snapshots VALUES(?,?,?,?,?,?)',(date,date+'T20:00:00Z','audit-'+date,'COMPLETE_VALIDATED',17,date+'T21:00:00Z'))
 for i,category in enumerate(registry):
  key=category['category_key'];con.execute('INSERT OR REPLACE INTO category_days VALUES(?,?,?,?,?,?)',(date,key,category['source_url'],30,1,'[]'))
  for j in range(1,31):
   asin='B'+f'{i:03}{j:06}';rank=j
   if i==0 and j==1:asin='B0BVGSX46M';rank=1 if n==6 else 30
   if i==0 and j==30:rank=30 if n==6 else 1
   if i==3 and j==1:asin='B000000001';rank=1 if n==6 else 30
   if i==3 and j==30:rank=30 if n==6 else 1
   title=f'Audit {key} Product {j}';price=float(10+j);reviews=50 if i==0 and j==1 else 100+n*20
   con.execute('INSERT OR REPLACE INTO observations VALUES(?,?,?,?,?,?,?,?,?)',(date,key,rank,asin,title,'https://www.amazon.com/dp/'+asin,price,4.8,reviews))
   ptype=['electric_pressure_washer','gas_pressure_washer','cordless_pressure_washer','surface_cleaner'][j%4]
   con.execute('INSERT OR REPLACE INTO product_metadata VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',('AMAZON_US',asin,ptype,'high','audit-rule','audit-v1','[]','Audit Brand','Audit Brand','audit-brand',None,'verified_metadata',dates[0],dates[-1]))
for n in range(55):
 date=(datetime.date(2026,10,18)-datetime.timedelta(days=n)).isoformat();key=f'daily/{date}/pressure_washers.pdf'
 con.execute('INSERT OR REPLACE INTO reports VALUES(?,?,?,?,?,?,?,?)',(key,date,'pressure_washers','all','daily','Audit daily report',100,date+'T22:00:00Z'))
con.commit();print(json.dumps({'isolated':str(root),'dates':len(dates),'categories':len(registry),'observations':con.execute('SELECT COUNT(*) FROM observations').fetchone()[0]}));con.close()
