'use client';
import type { MarketContext } from '@/lib/market-context';
import { serializeMarketContext } from '@/lib/market-context';
import { type buildWorthStudyingProducts, formatExactNumber } from '@/lib/ui-intelligence';
import { ProductIdentity } from './ProductIdentity';
import { RankDelta, RankDisplay } from './RankDisplay';
import { useViewQuery } from './useViewQuery';
import { RetryPage } from './RetryPage';

export function WorthStudying({rows,context,marketDate,baselineDate,completeDays,updatedAt,failed,source}: {
 rows:ReturnType<typeof buildWorthStudyingProducts>;context:MarketContext;marketDate:string;
 baselineDate:string|null;completeDays:number;updatedAt:string;failed:boolean;source:'/market'|'/reports';
}) {
 const {params}=useViewQuery();
 const query=serializeMarketContext(context,{date:marketDate});
 const returnTo=`${source}?${params.toString()||query}`;
 return <section className="sectionBlock worthStudying"><div className="sectionHeading"><div><h2>值得研究</h2><p>保留低评论与显著排名上升规则；研究优先级不代表成交概率或销量预测。</p></div></div>
  <div className="opportunityGuide" aria-label="值得研究阅读说明"><strong>怎么读</strong><span>先看为什么入选，再看数据依据和证据缺口；下一步打开产品数据进行人工核验。</span></div>
  <p>指标比较区间：{baselineDate??'比较日不足'} 至 {marketDate} · {completeDays} 个完整市场日</p><p>数据更新：{updatedAt}</p>
  {failed?<div role="alert"><p>实时研究数据读取失败，当前回退数据不用于生成新的候选结论。</p><RetryPage/></div>:!baselineDate?<p role="status">缺少可验证比较日，暂不判断研究候选。<a href={`/rankings?${query}`} target="_top">查看市场数据 →</a></p>:rows.length?<div className="rankingSurface tableScroll"><table><thead><tr><th>产品</th><th>为什么入选</th><th>数据依据</th><th>还需核验</th><th>下一步</th></tr></thead><tbody>{rows.map(row=>{const missing=[row.price===null?'价格':null,row.rating===null?'评分':null].filter(Boolean);return <tr key={row.asin}><td><ProductIdentity asin={row.asin} title={row.title} brand={row.brand} type={row.productType} href={`/products/${row.asin}?${query}&returnTo=${encodeURIComponent(returnTo)}`}/></td><td><strong>研究结论</strong><p>{row.reason}</p></td><td><dl className="opportunityFacts"><div><dt>当前排名</dt><dd><RankDisplay rank={row.rank}/></dd></div><div><dt>1D变化</dt><dd><RankDelta delta={row.delta}/></dd></div><div><dt>评论数</dt><dd>{formatExactNumber(row.reviews)}</dd></div></dl></td><td><strong>证据缺口</strong><p>{missing.length?missing.join('、'):'当前展示指标无缺失'}</p><p>需求、竞争、差异化及销售障碍仍需人工核验。</p></td><td><a href={`/products/${row.asin}?${query}&returnTo=${encodeURIComponent(returnTo)}`} target="_top">查看产品数据 →</a><a href={`/rankings?${query}`} target="_top">查看同市场榜单 →</a></td></tr>})}</tbody></table></div>:<p role="status">当前没有同时满足低评论与显著排名上升条件的商品。<a href={`/rankings?${query}`} target="_top">查看市场数据 →</a></p>}
 </section>;
}
