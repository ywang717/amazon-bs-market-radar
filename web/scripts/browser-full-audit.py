"""Real Chromium acceptance. Protected writes require explicitly isolated localhost."""
import argparse,asyncio,copy,json,re,traceback
from pathlib import Path
from urllib.parse import urlparse,parse_qs
from urllib.request import getproxies
from playwright.async_api import async_playwright,expect
args=argparse.ArgumentParser();args.add_argument('--base',default='http://127.0.0.1:3199');args.add_argument('--write-fixtures',action='store_true');args.add_argument('--groups',default='inventory,navigation,products,rankings,reports,garden,review,errors,api,extra');args.add_argument('--output',required=True);args=args.parse_args()
BASE=args.base.rstrip('/');OUT=Path(args.output).resolve();OUT.mkdir(parents=True,exist_ok=True)
if args.write_fixtures and urlparse(BASE).hostname not in ['127.0.0.1','localhost']:raise SystemExit('Protected test writes are restricted to isolated localhost')
checks=[];console=[];network=[];inventory=[];phase='init';payloads=[];responses=[]
registry=json.loads((Path(__file__).resolve().parents[1]/'config/category-registry.json').read_text())['categories'];garden=[r for r in registry if r['category_key']=='patio_lawn_garden' or r['category_key'].startswith('garden_')]
def log(name,detail=None,status='PASS'):
 row={'name':name,'status':status,'detail':detail};checks.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
async def main():
 global phase
 async with async_playwright() as pw:
  options={'headless':True}
  if urlparse(BASE).hostname not in ['127.0.0.1','localhost']:options['proxy']={'server':getproxies()['https']}
  browser=await pw.chromium.launch(**options);ctx=await browser.new_context(viewport={'width':1440,'height':1000},accept_downloads=True);p=await ctx.new_page()
  ctx.on('response',lambda r:responses.append({'phase':phase,'url':r.url,'status':r.status}) if '/api/' in r.url or r.request.resource_type=='document' else None)
  ctx.on('response',lambda r:network.append({'phase':phase,'url':r.url,'status':r.status}) if r.status>=400 else None)
  p.on('console',lambda m:console.append({'phase':phase,'kind':'console','message':m.text}) if m.type=='error' else None)
  p.on('pageerror',lambda e:console.append({'phase':phase,'kind':'pageerror','message':e.stack}))
  if args.write_fixtures:ctx.on('request',lambda r:payloads.append(r.post_data_json) if r.method=='POST' and '/api/sync/v1/garden-reviews' in r.url else None)
  async def goto(path):
   await p.goto(BASE+path,wait_until='networkidle',timeout=45000)
  async def settled():await p.wait_for_load_state('networkidle',timeout=45000)
  async def query(key,value):
   await p.wait_for_url(lambda u:parse_qs(urlparse(u).query).get(key)==([value] if value is not None else None),wait_until='domcontentloaded');await settled()
  async def api(path,method='GET',body=None,authorized=False):
   return await p.evaluate('''async ({path,method,body,authorized})=>{const r=await fetch(path,{method,headers:{...(body?{'Content-Type':'application/json'}:{}),...(authorized?{Authorization:'Bearer local-audit-token'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,text:await r.text()}}''',{'path':path,'method':method,'body':body,'authorized':authorized})
  async def run(name,fn):
   global phase
   if name not in args.groups.split(','):return
   phase=name
   try:await fn()
   except Exception as e:log(name,{'error':str(e).split('Call log:')[0][:500],'trace':traceback.format_exc().split('Call log:')[0][:1800]},'FAIL');await p.screenshot(path=str(OUT/(name+'-failure.png')))
  async def inspect():
   for path in ['/','/market','/products','/products/B0BVGSX46M','/brands','/rankings','/reports','/analysis','/insights','/methodology','/garden','/garden/products','/garden/opportunities','/garden/review']:
    await goto(path+('?' if '?' not in path else '&')+'category=pressure_washers&segment=all')
    assert await p.locator('main').count()==1
    assert await p.locator('#primary-navigation a[aria-current="page"]').count()<=1
    controls=await p.locator('main button,main select,main input,main summary').evaluate_all('(es)=>es.map(e=>({tag:e.tagName,name:e.getAttribute("aria-label")||e.getAttribute("placeholder")||e.getAttribute("name")||e.textContent.trim().slice(0,60),type:e.getAttribute("type"),disabled:e.disabled||false}))')
    await p.screenshot(path=str(OUT/('desktop-'+(path.replace('/','-').strip('-') or 'home')+'.png')),full_page=True)
    inventory.append({'route':path,'title':await p.title(),'controls':controls});log('页面可访问 '+path)
  await run('inventory',inspect)
  async def navigation():
   await goto('/products?date=2026-10-18&category=pressure_washers&segment=all')
   for label,path in [('总览','/'),('市场','/market'),('产品','/products'),('品牌','/brands'),('榜单','/rankings'),('报告','/reports'),('庭院与花园','/garden')]:
    await p.locator('#primary-navigation').get_by_role('link',name=label,exact=True).click();await settled();assert urlparse(p.url).path==path;log('主导航 '+label)
   await p.set_viewport_size({'width':390,'height':844});await p.get_by_role('button',name='打开主导航',exact=True).click();await expect(p.get_by_role('button',name='关闭主导航',exact=True)).to_have_attribute('aria-expanded','true');await p.get_by_role('button',name='关闭主导航',exact=True).press('Escape')
   # Escape closes drawers; the menu is explicitly closed by its toggle.
   if await p.get_by_role('button',name='关闭主导航',exact=True).count():await p.get_by_role('button',name='关闭主导航',exact=True).click()
   assert await p.evaluate('document.documentElement.scrollWidth<=window.innerWidth');log('移动菜单及页面宽度');await p.set_viewport_size({'width':1440,'height':1000})
   await goto('/products?date=2026-10-18&category=pressure_washers&segment=all')
   for name in ['市场动态','数据状态']:
    await p.get_by_role('button',name=name,exact=True).click();dialog=p.get_by_role('dialog',name=name);await dialog.wait_for();await settled();assert not await dialog.get_by_text('数据暂时无法载入',exact=True).count();await p.keyboard.press('Escape');await dialog.wait_for(state='hidden');log('顶栏面板及Escape '+name)
   await goto('/market?date=2026-10-18&category=pressure_washers&segment=all')
   for days in ['7','30']:
    await p.locator('.marketWindowBar').get_by_role('link',name=days+'D',exact=True).click();await query('window',days);log('市场窗口 '+days)
   for label,key in [('排名变化','movers'),('入榜 / 出榜','entrants'),('概览','overview')]:
    await p.locator('.marketViewTabs').get_by_role('link',name=label,exact=True).click();await query('view',key);log('市场视图 '+label)
  await run('navigation',navigation)
  async def products():
   await goto('/products?date=2026-10-18&category=pressure_washers&segment=all')
   for group in ['产品筛选','产品类型筛选']:
    scope=p.get_by_role('group',name=group,exact=True)
    for label in await scope.get_by_role('button').all_text_contents():
     button=scope.get_by_role('button',name=label,exact=True);await button.click();await expect(button).to_have_attribute('aria-pressed','true');log(group+' '+label,{'rows':await p.locator('.productBrowserTable tbody tr').count()})
    await scope.get_by_role('button').first.click()
   await p.get_by_placeholder('搜索 ASIN / 产品 / 品牌').fill('B0BVGSX46M');await expect(p.locator('.productBrowserTable tbody tr')).to_have_count(1);await p.reload(wait_until='networkidle');await expect(p.locator('.productBrowserTable tbody tr')).to_have_count(1)
   original=p.url;await p.locator('.productIdentity a').first.click();await settled();point=p.locator('button.historyPoint').last;await point.click();await expect(point).to_have_attribute('aria-expanded','true');await point.press('Enter');await expect(point).to_have_attribute('aria-expanded','false');await p.locator('.backLink').click();await settled();assert p.url==original;log('产品筛选刷新/详情/时间线/返回恢复')
   await p.get_by_role('button',name='清除产品筛选',exact=True).click();await expect(p.locator('.productBrowserTable tbody tr')).to_have_count(30);assert parse_qs(urlparse(p.url).query)['date']==['2026-10-18'];await p.get_by_placeholder('搜索 ASIN / 产品 / 品牌').fill('audit-no-match');await p.get_by_role('heading',name='没有匹配产品',exact=True).wait_for();log('产品清除及无匹配状态')
  await run('products',products)
  async def rankings():
   await goto('/rankings?date=2026-10-18&category=pressure_washers&segment=all')
   for option in ['10','20','30']:
    await p.locator('.filterBar select').select_option(option);await expect(p.locator('.rankingTable tbody tr')).to_have_count(int(option));log('榜单范围 '+option)
   await p.go_back();await settled();await expect(p.locator('.filterBar select')).to_have_value('20');await p.go_forward();await settled();await expect(p.locator('.filterBar select')).to_have_value('30');log('浏览器前进后退恢复筛选')
   await p.get_by_placeholder('输入产品、品牌或 ASIN').fill('B0BVGSX46M');await expect(p.locator('.rankingTable tbody tr')).to_have_count(1);before=p.url;await p.reload(wait_until='networkidle');await p.locator('.productIdentity a').first.click();await settled();await p.locator('.backLink').click();await settled();assert p.url==before;log('榜单搜索刷新及返回恢复')
   await p.get_by_role('button',name='清除榜单筛选',exact=True).click();await expect(p.locator('.rankingTable tbody tr')).to_have_count(30);log('清除榜单筛选')
   category=p.get_by_label('市场分类',exact=True);opts=await category.locator('option').evaluate_all('(es)=>es.map(e=>({value:e.value,label:e.textContent}))')
   for item in opts:
    await category.select_option(item['value']);await query('category',item['value'])
    segments=await p.get_by_label('市场分群',exact=True).locator('option').evaluate_all('(es)=>es.map(e=>e.value)')
    for value in segments:
     await p.get_by_label('市场分群',exact=True).select_option(value);await query('segment',value);log('市场分群 '+item['value']+'/'+value)
   await category.select_option('pressure_washers');await query('category','pressure_washers')
   dates=await p.get_by_label('市场日期',exact=True).locator('option').evaluate_all('(es)=>es.map(e=>e.value)')
   for value in dates:
    await p.get_by_label('市场日期',exact=True).select_option(value);await query('date',value);log('有效市场日 '+value)
  await run('rankings',rankings)
  async def reports():
   await goto('/reports?date=2026-10-18&category=pressure_washers&segment=all')
   await expect(p.locator('#report-archive article').first).to_be_visible();assert await p.locator('#report-archive article').count()<=20
   pages=p.get_by_role('navigation',name='报告归档分页');await pages.get_by_role('button',name='下一页',exact=True).click();assert parse_qs(urlparse(p.url).query)['archivePage']==['2'];await p.reload(wait_until='networkidle');await expect(pages).to_contain_text('第 2 /');await pages.get_by_role('button',name='上一页',exact=True).click();log('报告20条分页与刷新')
   await p.get_by_label('归档日期（独立于市场日期）',exact=True).fill('2026-10-12');await query('archiveDate','2026-10-12');await expect(p.locator('#report-archive article').first).to_be_visible();assert all('2026-10-12' in text for text in await p.locator('#report-archive article').all_text_contents());assert parse_qs(urlparse(p.url).query)['date']==['2026-10-18'];log('独立归档日期与市场日期分离')
   for label,kind in [('周报','weekly'),('日报','daily'),('全部报告⌄','all')]:
    await p.locator('.archiveFilters').get_by_role('link',name=label,exact=True).click();await query('kind',kind);assert parse_qs(urlparse(p.url).query)['archiveDate']==['2026-10-12'];log('归档类型保留日期 '+label)
   research=p.locator('.worthStudying .productIdentity a').first
   if await research.count():
    before=p.url;await research.click();await settled();await p.locator('.backLink').click();await settled();assert p.url==before;log('报告研究详情返回保留归档条件')
   await p.get_by_role('button',name='全部归档日期',exact=True).click();await query('archiveDate',None);await expect(p.locator('#report-archive article').first).to_be_visible();detail=p.locator('details.signalEvidence').filter(has=p.get_by_text('证据与方法',exact=True));await detail.locator('summary').click();assert await detail.get_attribute('open') is not None;await detail.locator('summary').press('Enter');assert await detail.get_attribute('open') is None;log('全部归档与证据展开关闭')
  await run('reports',reports)
  async def garden_flow():
   await goto('/garden/products');category=p.locator('.gardenFilters select').nth(0)
   for option in await category.locator('option').evaluate_all('(es)=>es.map(e=>({value:e.value,label:e.textContent}))'):
    if not option['value']:continue
    await category.select_option(option['value']);await expect(p.locator('.gardenCards>article')).to_have_count(30);assert all(s.startswith(option['label']+' · #') for s in await p.locator('.gardenCards .gardenBadge').all_text_contents());log('园艺分类 '+option['value'])
   await p.get_by_role('button',name='清除筛选',exact=True).click();await p.get_by_role('navigation',name='园艺产品分页').get_by_role('button',name='下一页').click();assert parse_qs(urlparse(p.url).query)['page']==['2'];first=await p.locator('.gardenCards>article').first.inner_text();await p.reload(wait_until='networkidle');assert await p.locator('.gardenCards>article').first.inner_text()==first;log('园艺30条分页刷新')
   await p.get_by_role('button',name='清除筛选',exact=True).click()
   for option in await p.get_by_label('机会信号',exact=True).locator('option').evaluate_all('(es)=>es.map(e=>e.value)'):
    await p.get_by_label('机会信号',exact=True).select_option(option);log('园艺信号 '+(option or 'all'))
   await p.get_by_label('机会信号',exact=True).select_option('');await p.get_by_label('最低价格（USD）',exact=True).fill('15');await p.get_by_label('最高价格（USD）',exact=True).fill('30')
   for sort in ['rank','price','confidence','score']:
    await p.get_by_label('排序',exact=True).select_option(sort);prices=await p.locator('.gardenMetrics dd').evaluate_all('(es)=>es.filter((e,i)=>i%4===0).map(e=>Number(e.textContent.replace("$","")))');assert prices and all(15<=v<=30 for v in prices)
    if sort=='price':assert prices==sorted(prices)
    log('园艺价格/排序 '+sort)
   detail=p.locator('.gardenCards details').first;await detail.locator('summary').click();assert await detail.get_attribute('open') is not None;await detail.locator('summary').click();log('园艺历史展开收起')
   await p.get_by_label('最低价格（USD）',exact=True).fill('50');await expect(p.get_by_role('alert').filter(has_text='最低价格')).to_be_visible();log('无效价格区间提示')
   await goto('/garden/opportunities');await p.locator('.publishedReviews').wait_for();await settled()
   candidates=p.locator('.gardenCards>article').filter(has=p.get_by_role('link',name='查看证据与核验 →',exact=True))
   if await candidates.count():
    item=candidates.first;await expect(item).to_contain_text('指标比较区间');await expect(item).to_contain_text('证据缺口');before=p.url;await item.get_by_role('link',name='查看证据与核验 →',exact=True).click();await p.locator('.gardenEditor').wait_for();assert await p.get_by_label('ASIN',exact=True).input_value();assert await p.get_by_label('所属榜单',exact=True).input_value();await p.get_by_role('link',name='← 返回商机列表',exact=True).click();await settled();assert p.url==before;log('商机依据/预填核验/返回')
   else:assert await p.get_by_role('heading',name=re.compile('完整市场日不足|暂无达到初筛条件')).count();log('商机无候选原因')
   for status in ['', 'observation','pending_verification','worth_validating','not_recommended']:
    await p.get_by_label('核验结果',exact=True).select_option(status);log('公开核验状态筛选 '+(status or 'all'))
   await p.get_by_label('核验 ASIN',exact=True).fill('no-match');await p.get_by_role('button',name='清除核验筛选').click();assert await p.get_by_label('核验 ASIN',exact=True).input_value()=='';log('公开核验ASIN与清除')
  await run('garden',garden_flow)
  async def review():
   if not args.write_fixtures:log('受保护成功写入',{'reason':'生产环境不写测试记录'},'ISOLATED_ONLY');return
   key=garden[0]['category_key'];await goto('/garden/review?asin=B000000001&categoryKey='+key)
   assert await p.get_by_role('button',name='保存核验版本',exact=True).is_disabled();
   for category in garden:
    await p.get_by_label('所属榜单',exact=True).select_option(category['category_key']);assert await p.get_by_label('所属榜单',exact=True).input_value()==category['category_key'];log('核验注册分类 '+category['category_key'])
   await p.get_by_label('所属榜单',exact=True).select_option(key);await p.get_by_label('同步凭证',exact=True).fill('wrong-local-audit-token');await p.get_by_role('button',name='读取最新核验与版本',exact=True).click();await p.get_by_text('同步凭证无效或没有读取权限',exact=True).wait_for();await p.get_by_label('同步凭证',exact=True).fill('local-audit-token')
   await p.get_by_role('button',name='读取最新核验与版本',exact=True).click();await expect(p.get_by_text('当前对象尚无核验版本，可以保存新的草稿。',exact=True)).to_be_visible()
   for i,label in enumerate(['需求','竞争','差异化','销售可行性限制']):
    group=p.locator('fieldset.reviewDimension').nth(i);await group.get_by_label('证据结论',exact=True).fill(label+' market evidence')
    for n in range(2):
     await group.get_by_role('button',name='添加'+label+'来源',exact=True).click();source=group.locator('.reviewSource').nth(n);await source.get_by_label('来源引用',exact=True).fill('private-audit-'+label+'-'+str(n));await source.get_by_label('来源日期',exact=True).fill('2026-10-18');await source.get_by_label('来源类型',exact=True).select_option('order');await source.get_by_label('有效期至（可选）',exact=True).fill('2030-12-31')
    await group.get_by_role('checkbox').check()
   
   for kind in ['invoice','settlement','order','quote','official_fee','assumption','exchange_rate']:
    await p.locator('fieldset.reviewDimension').first.get_by_label('来源类型',exact=True).first.select_option(kind);log('核验来源类型 '+kind)
   await p.locator('fieldset.reviewDimension').first.get_by_label('来源类型',exact=True).first.select_option('order');await p.locator('fieldset.reviewDimension').first.get_by_role('checkbox').check()
   for status in ['observation','pending_verification','not_recommended','worth_validating']:
    await p.get_by_label('核验状态',exact=True).select_option(status);log('核验表单状态 '+status)
   for basis in ['sales_barrier','market']:
    await p.get_by_label('暂不建议依据',exact=True).select_option(basis)
   await p.get_by_label('核验状态',exact=True).select_option('worth_validating');await p.get_by_role('checkbox',name=re.compile('已核验可合法上架')).check();await p.get_by_role('checkbox',name=re.compile('已人工确认当前版本')).check();await p.get_by_role('checkbox',name='发布该版本的公开摘要',exact=True).check();await p.get_by_role('button',name='保存核验版本',exact=True).click();await expect(p.get_by_text('实际核验状态：值得进一步验证',exact=True)).to_be_visible();assert payloads[-1]['assessment']['manualConfirmed'];log('隔离存储完整核验保存/发布')
   await p.get_by_role('button',name='读取最新核验与版本',exact=True).click();group=p.locator('fieldset.reviewDimension').first;await expect(group.locator('.reviewSource')).to_have_count(2);await group.get_by_label('来源引用',exact=True).first.fill('private-audit-edited');assert not await p.get_by_role('checkbox',name=re.compile('已人工确认当前版本')).is_checked();await group.get_by_role('checkbox').check();await p.get_by_role('checkbox',name=re.compile('已人工确认当前版本')).check();await p.get_by_role('button',name='保存核验版本',exact=True).click();await expect(p.get_by_text(re.compile('版本 2 已保存'))).to_be_visible();sources=payloads[-1]['assessment']['dimensions']['demand']['sources'];assert len(sources)==2 and sources[0]['kind']=='order' and sources[0]['expiresAt']=='2030-12-31' and sources[1]['reference']=='private-audit-需求-1';log('多来源编辑完整往返与重新确认')
   pub=await api('/api/public/garden-reviews');assert pub['status']==200 and 'private-audit-' not in pub['text'];assert json.loads(pub['text'])['reviews'][0]['dimensions']['demand']['sourceCount']==2;log('公开摘要不泄露完整来源')
   newer=copy.deepcopy(payloads[-1]);newer.update(revision=3,previousRevision=2);newer['assessment'].update(reviewRevision=3,confirmedReviewRevision=3)
   assert (await api('/api/sync/v1/garden-reviews','POST',newer,True))['status']==201
   await group.get_by_label('证据结论',exact=True).fill('retained draft after conflict');await p.get_by_role('checkbox',name='发布该版本的公开摘要',exact=True).uncheck();await p.get_by_role('button',name='保存核验版本',exact=True).click();await expect(p.get_by_text(re.compile('版本冲突：服务器已有较新版本'))).to_be_visible();assert await group.get_by_label('证据结论',exact=True).input_value()=='retained draft after conflict';assert await p.get_by_role('button',name='保存核验版本',exact=True).is_disabled();log('隔离版本冲突保留输入并阻止重复保存')
   p.once('dialog',lambda d:asyncio.create_task(d.accept()));await p.get_by_role('button',name='重新读取最新版本',exact=True).click();await expect(p.locator('.gardenEditor>p[role=status]')).to_contain_text('当前版本 3');log('冲突后显式重新读取最新版本')
   await p.screenshot(path=str(OUT/'review-isolated.png'))
   before_posts=len(payloads)
   legacy=copy.deepcopy(newer);legacy['assessment'].update(assessmentVersion='legacy_v1',economicsRevision=3,confirmedEconomicsRevision=3)
   economic={'amount':'20','status':'verified','currency':'USD','unit':'unit','specification':'audit','conditions':'audit','source':{'reference':'legacy-private','date':'2026-10-18','kind':'quote'}}
   legacy['economicsInput']={'mode':'forecast','currency':'USD','asOf':'2026-10-18','revision':3,'salePrice':economic,'costs':[]}
   async def legacy_read(route):await route.fulfill(json={'latest':legacy,'history':[{'revision':3}]})
   await p.route('**/api/sync/v1/garden-reviews?*',legacy_read);await p.get_by_role('button',name='读取最新核验与版本',exact=True).click();await p.get_by_role('button',name='创建市场口径新版本',exact=True).wait_for();assert await p.get_by_role('button',name='保存核验版本',exact=True).is_disabled();assert len(payloads)==before_posts
   await p.get_by_role('button',name='创建市场口径新版本',exact=True).click();assert not await p.get_by_role('checkbox',name='发布该版本的公开摘要',exact=True).is_checked();log('旧口径只读且不自动迁移发布')
   demand=p.locator('fieldset.reviewDimension').first
   for _ in range(18):await demand.get_by_role('button',name='添加需求来源',exact=True).click()
   await expect(demand.locator('.reviewSource')).to_have_count(20);assert await demand.get_by_role('button',name='添加需求来源',exact=True).is_disabled()
   await demand.get_by_role('button',name='删除需求来源3',exact=True).click();await expect(demand.locator('.reviewSource')).to_have_count(19);assert await demand.get_by_label('来源引用',exact=True).nth(1).input_value()=='private-audit-需求-1';log('每维度20来源上限与删除保留其他来源')
   await p.unroute('**/api/sync/v1/garden-reviews?*',legacy_read)
   assert await p.evaluate('!JSON.stringify(localStorage).includes("local-audit-token")&&!JSON.stringify(sessionStorage).includes("local-audit-token")');assert 'local-audit-token' not in p.url
   p.once('dialog',lambda d:asyncio.create_task(d.accept()));await p.get_by_label('ASIN',exact=True).fill('B000000099');await expect(p.locator('.reviewSource')).to_have_count(0);assert not await p.get_by_role('checkbox',name=re.compile('已人工确认当前版本')).is_checked();log('切换对象清空证据和确认，凭证未持久化')
   p.once('dialog',lambda d:asyncio.create_task(d.accept()));await goto('/garden/opportunities')
   published=p.locator('.publishedReviews');await expect(published.locator('.gardenCards>article')).to_have_count(1)
   for value in ['observation','pending_verification','worth_validating','not_recommended']:
    await published.get_by_label('核验结果',exact=True).select_option(value);await expect(published.locator('.gardenCards>article')).to_have_count(1 if value=='worth_validating' else 0)
   await published.get_by_role('button',name='清除核验筛选',exact=True).click();await expect(published.locator('.gardenCards>article')).to_have_count(1);log('已发布真实核验的四状态筛选与清除')
   for category in garden:
    await published.get_by_label('核验所属榜单',exact=True).select_option(category['category_key']);await expect(published.locator('.gardenCards>article')).to_have_count(1 if category['category_key']==key else 0)
   await published.get_by_role('button',name='清除核验筛选',exact=True).click();await published.get_by_role('link',name='查看核验 →',exact=True).click();await p.locator('.gardenEditor').wait_for();assert await p.get_by_label('同步凭证',exact=True).input_value()=='';assert await p.get_by_label('ASIN',exact=True).input_value()=='B000000001';log('公开核验分类及返回受保护页不会恢复凭证')
  await run('review',review)
  async def errors():
   async def fail(route):await route.fulfill(status=503,json={'error':'audit_fixture_unavailable'})
   await p.route('**/api/public/reports?*',fail);await goto('/reports?date=2026-10-18&category=pressure_washers&segment=all');await p.get_by_role('button',name='重试读取报告',exact=True).wait_for();assert '暂无已验证报告归档' not in await p.locator('#report-archive').inner_text();await p.unroute('**/api/public/reports?*',fail);await p.get_by_role('button',name='重试读取报告',exact=True).click();await expect(p.locator('#report-archive article').first).to_be_visible();log('报告503与重试恢复')
   async def malformed(route):await route.fulfill(json={'unexpected':[]})
   await p.route('**/api/public/reports?*',malformed);await p.reload(wait_until='networkidle');await p.get_by_role('button',name='重试读取报告',exact=True).wait_for();await p.unroute('**/api/public/reports?*',malformed);log('报告格式错误不伪装为空归档')
   await p.route('**/api/public/garden-reviews',fail);await goto('/garden/opportunities');await p.get_by_role('button',name='重试读取核验',exact=True).wait_for();await p.unroute('**/api/public/garden-reviews',fail);await p.get_by_role('button',name='重试读取核验',exact=True).click();await expect(p.get_by_role('button',name='重试读取核验',exact=True)).to_have_count(0);log('公开核验503与重试恢复')
   live=await api('/api/public/analysis/live?date=2026-10-18&category=pressure_washers&segment=all&kind=daily');assert live['status']==200;report=json.loads(live['text'])
   row={key:report[key] for key in ['key','marketDate','categoryKey','segmentKey','generatedAt','generatorVersion']};row['report_kind']='daily'
   async def listing(route):await route.fulfill(json={'reports':[row]})
   async def report_ok(route):await route.fulfill(json=report)
   await p.route('**/api/public/analysis?*',listing);await p.route('**/api/public/analysis/daily/**',fail)
   await goto('/analysis?date=2026-10-18&category=pressure_washers&segment=all');await p.locator('.analysisControls').get_by_role('button',name='历史归档',exact=True).click();await p.get_by_role('button',name='在线阅读',exact=True).click();await p.get_by_text('智能报告读取失败，请重试。',exact=True).wait_for();await p.unroute('**/api/public/analysis/daily/**',fail);await p.route('**/api/public/analysis/daily/**',report_ok);await p.get_by_role('button',name='重试在线阅读',exact=True).click();await p.locator('.analysisBody').wait_for();log('智能报告在线阅读失败提示与重试恢复')
   await p.unroute('**/api/public/analysis?*',listing);await p.unroute('**/api/public/analysis/daily/**',report_ok)
  await run('errors',errors)
  async def api_contracts():
   await goto('/garden')
   for item in registry:
    data=await api('/api/public/rankings?date=2026-10-18&category='+item['category_key']+'&segment=all');assert data['status']==200,(item['category_key'],data['status']);assert len(json.loads(data['text'])['observations'])==30;log('分类接口 '+item['category_key'])
   for bad in ['not-a-date','2026-02-30']:
    assert (await api('/api/public/reports?category=pressure_washers&segment=all&archiveDate='+bad))['status']==400
   assert json.loads((await api('/api/public/reports?category=pressure_washers&segment=all&archiveDate=2000-01-01'))['text'])['reports']==[]
   for path in ['/api/sync/v1/garden-reviews?asin=B000000001&categoryKey='+garden[0]['category_key']]:assert (await api(path))['status']==401
   health=await api('/api/health');assert json.loads(health['text'])['database'];log('接口参数/权限/健康状态')
  await run('api',api_contracts)
  async def extra():
   for path in ['/','/brands','/insights','/methodology','/garden','/garden/products','/garden/opportunities','/garden/review']:
    await goto(path)
    for d in await p.locator('main details').all():
     initial=await d.get_attribute('open');await d.locator('summary').click();assert (await d.get_attribute('open') is None)!=(initial is None);await d.locator('summary').press('Enter');assert await d.get_attribute('open')==initial
    await p.set_viewport_size({'width':390,'height':844});assert await p.evaluate('document.documentElement.scrollWidth<=innerWidth'),path;await p.screenshot(path=str(OUT/('mobile-'+path.replace('/','-').strip('-')+'.png')));await p.set_viewport_size({'width':1440,'height':1000});log('补充页面展开/键盘/移动宽度 '+path)
   await goto('/market?date=2026-10-18&category=pressure_washers&segment=all')
   section=p.locator('.worthStudying');await expect(section).to_contain_text('指标比较区间');await expect(section).to_contain_text('不代表成交概率或销量预测')
   link=section.locator('.productIdentity a').first
   if await link.count():
    before=p.url;await link.click();await settled();await p.locator('.backLink').click();await settled();assert p.url==before;log('主站研究入口详情与返回')
   else:await expect(section).to_contain_text('当前没有同时满足');log('主站研究入口未达条件原因')
   await goto('/analysis?workspace=seller_alert&date=2026-10-18&category=pressure_washers&segment=all')
   for label,value in [('High','high'),('Watch','watch'),('市场动态','activity'),('High + Watch',None)]:
    await p.locator('.alertFilterTabs').get_by_role('link',name=label,exact=True).click();await settled();assert parse_qs(urlparse(p.url).query).get('alert')==([value] if value else None);log('卖家预警筛选 '+label)
   for label,value in [('竞争观察','competition_strategy'),('历史归档','archive'),('经营预警','seller_alert'),('历史归档','archive')]:
    await p.locator('.sellerWorkspaceControls nav').get_by_role('link',name=label,exact=True).click();await settled();assert parse_qs(urlparse(p.url).query)['workspace']==[value];log('卖家工作区 '+label)
   for profile in ['competition_strategy','seller_alert']:
    await p.locator('select[name=profile]').select_option(profile);await p.locator('input[name=archiveDate]').fill('2000-01-01');await p.get_by_role('button',name='应用筛选',exact=True).click();await settled();await expect(p.locator('.sellerArchiveList')).to_contain_text('暂无符合筛选条件的卖家归档');log('卖家健康空归档 '+profile)
   await p.locator('input[name=archiveDate]').fill('');await p.get_by_role('button',name='应用筛选',exact=True).click();await settled()
   read=p.locator('.sellerArchiveList a.downloadButton').first
   if await read.count():await read.click();await settled();await p.locator('.sellerSummaryBlock').wait_for();log('卖家归档在线阅读')
   else:log('卖家归档在线阅读',{'reason':'当前环境无真实归档可读'},'NOT_APPLICABLE')
   for label in ['经营预警','竞争观察','卖家历史归档','实时解读 / 历史归档']:
    await p.locator('.analysisCenterModeNav').get_by_role('link',name=label,exact=True).click();await settled();assert await p.locator('.analysisCenterModeNav a[aria-current=page]').inner_text()==label;log('智能工作区 '+label)
   for kind in ['weekly','daily']:
    await p.locator('.analysisControls select').select_option(kind);await p.locator('.analysisBody').wait_for();log('实时智能报告类型 '+kind)
   await goto('/insights');await p.get_by_role('link',name='查看方法说明 →',exact=True).click();await settled();assert urlparse(p.url).path=='/methodology';log('方法说明入口')
  await run('extra',extra)
  async def sync_retry():
   if not args.write_fixtures:raise RuntimeError('Sync retries are restricted to isolated storage')
   await goto('/garden');bundle=json.loads((Path(__file__).resolve().parents[2]/'var/amazon-bestsellers/2026-10-18/dashboard-sync-bundle.json').read_text(encoding='utf-8-sig'));bundle['marketDate']='2026-10-19';bundle['observedAt']='2026-10-19T20:00:00-07:00';bundle['receiptSha256']='c'*64
   remap={asin:'B9'+f'{i:08}' for i,asin in enumerate(sorted({row['asin'] for c in bundle['categories'] for row in c['observations']}),1)}
   for category in bundle['categories']:
    for row in category['observations']:row['asin']=remap[row['asin']];row['url']='https://www.amazon.com/dp/'+row['asin']
   for row in bundle['productMetadata']:row['asin']=remap[row['asin']]
   results=[]
   for _ in range(2):
    response=await api('/api/sync/v1/bundles','POST',bundle,True);assert response['status']==201,{'status':response['status'],'body':response['text']};results.append(json.loads(response['text']))
    for category in registry:
     rows=json.loads((await api('/api/public/rankings?date=2026-10-19&category='+category['category_key']+'&segment=all'))['text'])['observations'];assert len(rows)==30 and len({r['asin'] for r in rows})==30
   assert results[0]['observations']==results[1]['observations']==510;log('隔离实际同步及重复同步保持17分类各30条',{'responses':results})
  await run('sync',sync_retry)
  async def pairwise():
   for category in ['pressure_washers','sump_pumps','pressure_washer_accessories']:
    await goto('/products?date=2026-10-18&category='+category+'&segment=all');filters=p.get_by_role('group',name='产品筛选',exact=True);types=p.get_by_role('group',name='产品类型筛选',exact=True)
    values=await types.get_by_role('button').all_text_contents() if await types.count() else [None]
    for label in await filters.get_by_role('button').all_text_contents():
     await filters.get_by_role('button',name=label,exact=True).click()
     for value in values:
      if value is not None:await types.get_by_role('button',name=value,exact=True).click();await expect(types.get_by_role('button',name=value,exact=True)).to_have_attribute('aria-pressed','true')
      await expect(filters.get_by_role('button',name=label,exact=True)).to_have_attribute('aria-pressed','true');assert parse_qs(urlparse(p.url).query).get('filter')==([label] if label!='全部' else None);log('产品成对 '+category+'/'+label+'/'+str(value),{'rows':await p.locator('.productBrowserTable tbody tr').count()})
    await goto('/rankings?date=2026-10-18&category='+category+'&segment=all')
    segments=await p.get_by_label('市场分群',exact=True).locator('option').evaluate_all('(es)=>es.map(e=>e.value)')
    for segment in segments:
     await p.get_by_label('市场分群',exact=True).select_option(segment);await query('segment',segment)
     for limit in ['10','20','30']:
      await p.locator('.filterBar select').select_option(limit);assert await p.locator('.rankingTable tbody tr').count()<=int(limit);await query('limit',limit);log('榜单成对 '+category+'/'+segment+'/'+limit)
   await goto('/garden/products')
   for category in garden:
    await p.get_by_label('所属榜单',exact=True).select_option(category['category_key'])
    for sort in ['rank','price','confidence','score']:
     await p.get_by_label('排序',exact=True).select_option(sort);await expect(p.locator('.gardenCards>article')).to_have_count(30);log('园艺成对 '+category['category_key']+'/'+sort)
  await run('pairwise',pairwise)
  async def all_expansions():
   await goto('/products/B0BVGSX46M?date=2026-10-18&category=pressure_washers&segment=all')
   for point in await p.locator('button.historyPoint').all():
    name=await point.get_attribute('aria-label');await point.click();await expect(point).to_have_attribute('aria-expanded','true');await expect(p.locator('#rank-history-detail')).to_contain_text(name.split('，')[0]);await point.press('Enter');await expect(point).to_have_attribute('aria-expanded','false');log('时间线逐点 '+name)
   for path in ['/','/market','/reports','/insights','/garden/products','/methodology']:
    await goto(path+'?date=2026-10-18&category=pressure_washers&segment=all')
    n=0
    for d in await p.locator('main details').all():
     if not await d.is_visible():continue
     initial=await d.get_attribute('open');summary=d.locator(':scope>summary');await summary.click();assert (await d.get_attribute('open') is None)!=(initial is None);await summary.press('Enter');assert await d.get_attribute('open')==initial;n+=1
    log('逐项展开关闭 '+path,{'details':n})
   for link in await p.get_by_role('navigation',name='方法目录').get_by_role('link').all():
    target=await link.get_attribute('href');await link.click();assert urlparse(p.url).fragment==target[1:];await expect(p.locator(target)).to_be_visible()
   log('方法目录全部锚点')
  await run('expansions',all_expansions)
  phase='finished';await browser.close()
 report={'base':BASE,'browser':'local real Chromium','protected_writes':'isolated localhost only' if args.write_fixtures else 'not performed','checks':checks,'console':console,'network':network,'inventory':inventory,'responses':responses}
 (OUT/'audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps({'summary':{'pass':sum(c['status']=='PASS' for c in checks),'fail':sum(c['status']=='FAIL' for c in checks),'unexpected_console':[e for e in console if e['kind']=='pageerror' or not (e['phase'] in ['errors','api','review','sync'] and re.search(r'Failed to load resource.*(400|401|409|503)',e['message']))],'unexpected_http':[e for e in network if e['phase'] not in ['errors','api','review','sync']]}},ensure_ascii=False),flush=True)
asyncio.run(main())
