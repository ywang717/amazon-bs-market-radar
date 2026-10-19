"""Read-only capture/Postgres/production reconciliation; credentials never logged."""
import argparse, asyncio, json, os, subprocess
from datetime import datetime
from pathlib import Path
from urllib.request import getproxies
from urllib.parse import urlparse, parse_qs
from playwright.async_api import async_playwright
from historical_snapshots import load_captures, select_captures

async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--base', default='https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site')
    parser.add_argument('--provenance-json', help='Read-only Sites export containing receipt_sha256')
    parser.add_argument('--date', help='Limit verification to one receipt market date')
    parser.add_argument('--browser-executable')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = Path(args.output); output.mkdir(parents=True, exist_ok=True)
    captures, rejected = load_captures(root / 'var')
    published = None
    published_rows = {}
    if args.provenance_json:
        exported = json.loads(Path(args.provenance_json).read_text())
        records = exported if isinstance(exported, list) else [exported]
        published_rows = {row['market_date']: row for record in records for row in record.get('rows', [])}
        published = {date: row['receipt_sha256'] for date, row in published_rows.items()}
        if not published: raise ValueError('No published capture hashes in provenance export')
    selected = select_captures(captures, published, market_date=args.date)
    if args.date:
        selected = [c for c in selected if c['date'] == args.date]
        if published is not None: published = {d: s for d, s in published.items() if d == args.date}
    missing = [] if published is None else [d for d in published if d not in {c['date'] for c in selected}]
    config = json.loads((root / '.local/postgres-settings.json').read_text(encoding='utf-8-sig'))
    env = dict(os.environ, PGPASSWORD=config['password'], LANG='C', LC_ALL='C')
    sql = ('SET search_path TO amazon_intelligence,public; SELECT r.market_date,r.artifact_sha256,count(*) '
           'FROM best_sellers_observation o JOIN best_sellers_run r ON r.best_sellers_run_id=o.best_sellers_run_id '
           'GROUP BY r.market_date,r.artifact_sha256;')
    result = subprocess.run([str(Path(config['install_root']) / 'bin/psql.exe'), '-qAt', '-h', config['host'],
                             '-p', str(config['port']), '-U', config['username'], '-d', config['database'], '-c', sql],
                            env=env, text=True, capture_output=True)
    if result.returncode: raise RuntimeError('Read-only PostgreSQL reconciliation query failed')
    pg = {(parts[0], parts[1]): int(parts[2]) for line in result.stdout.splitlines()
          if len(parts := line.split('|')) == 3}
    checks, console, network = [], [], []
    async with async_playwright() as pw:
        options = {'headless': True}
        if args.browser_executable: options['executable_path'] = args.browser_executable
        if proxy := getproxies().get('https'): options['proxy'] = {'server': proxy}
        browser = await pw.chromium.launch(**options); page = await browser.new_page()
        page.on('pageerror', lambda error: console.append(str(error)))
        page.on('console', lambda message: console.append(message.text) if message.type == 'error' else None)
        page.on('response', lambda response: network.append({'url': response.url, 'status': response.status}) if response.status >= 400 else None)
        await page.goto(args.base + '/rankings?date=' + (args.date or '2026-10-18') + '&category=pressure_washers&segment=all', wait_until='networkidle', timeout=45000)
        for capture in selected:
            for category, expected in capture['rows'].items():
                ui_count = None
                if args.date:
                    await page.get_by_label('市场分类', exact=True).select_option(category)
                    await page.wait_for_url(lambda url: parse_qs(urlparse(url).query).get('category') == [category])
                    await page.wait_for_load_state('networkidle')
                    await page.locator('.filterBar select').select_option('30')
                    await page.wait_for_load_state('networkidle')
                    ui_count = await page.locator('.rankingTable tbody tr').count()
                    ui_rows = await page.locator('.rankingTable tbody tr').evaluate_all('''rows=>rows.map(row=>[Number(row.cells[1].textContent.replace(/[^0-9]/g,"")),new URL(row.querySelector(".productIdentity a").href).pathname.split("/").pop()])''')
                    if sorted(ui_rows) != [list(v) for v in expected]: raise AssertionError('Visible ranking differs from published capture: ' + category)
                    await page.screenshot(path=str(output / (category + '.png')), full_page=True)
                actual = await page.evaluate('''async ({date,category})=>{
                    const r=await fetch('/api/public/rankings?date='+date+'&category='+category+'&segment=all');
                    const body=await r.json();return {status:r.status,rows:(body.observations||[]).map(v=>[v.rank,v.asin])}
                }''', {'date': capture['date'], 'category': category})
                checks.append({'date': capture['date'], 'category': category, 'sha': capture['sha'],
                               'status': actual['status'], 'rows': len(actual['rows']), 'ui_count': ui_count,
                               'url': page.url if args.date else None,
                               'matches': actual['status'] == 200 and sorted(actual['rows']) == [list(v) for v in expected]})
        await browser.close()
    snapshots = [{**{k: v for k, v in c.items() if k != 'rows'},
                  'snapshot_count': sum(len(v) for v in c['rows'].values()),
                  'postgres_count': pg.get((c['date'], c['sha']))} for c in selected]
    timestamp_mismatches = []
    for capture in selected:
        if capture['date'] not in published_rows: continue
        source_time = capture['observed_at']
        published_time = published_rows[capture['date']].get('observed_at')
        try:
            source_date = datetime.fromisoformat(source_time.replace('Z', '+00:00'))
            published_date = datetime.fromisoformat(published_time.replace('Z', '+00:00'))
            if source_date.utcoffset() is None or published_date.utcoffset() is None:
                raise ValueError('Timestamp lacks an offset')
            difference = (published_date - source_date).total_seconds()
        except (ValueError, TypeError, AttributeError):
            difference = None
        if difference != 0:
            timestamp_mismatches.append({'date': capture['date'], 'source_observed_at': source_time,
                                         'published_observed_at': published_time, 'difference_seconds': difference})
    summary = {'selected_captures': len(selected), 'rejected_sources': len(rejected),
               'published_hashes_without_source': missing, 'website_queries': len(checks),
               'website_mismatch': [r for r in checks if not r['matches']],
               'postgres_capture_absent_or_different': [r['date'] for r in snapshots if r['postgres_count'] != r['snapshot_count']],
               'published_timestamp_mismatch': timestamp_mismatches,
               'console_errors': len(console), 'http_errors': len(network)}
    report = {'snapshots': snapshots, 'rejected_sources': rejected, 'website_checks': checks,
              'console': console, 'network': network, 'summary': summary}
    (output / 'data-reconciliation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    if not checks or missing or summary['website_mismatch'] or timestamp_mismatches or console or network: raise SystemExit(1)

if __name__ == '__main__': asyncio.run(main())
