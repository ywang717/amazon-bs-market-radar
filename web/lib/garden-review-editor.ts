import { MARKET_DIMENSIONS, type GardenOpportunityRecord, type GardenEvidence } from './garden-opportunity.ts';
import { economicSourceValid } from './garden-economics.ts';
type Dimensions = GardenOpportunityRecord['dimensions'];
type Dimension = typeof MARKET_DIMENSIONS[number];
type Source = GardenEvidence['sources'][number];
const labels = { demand: '需求', competition: '竞争', differentiation: '差异化', risk: '销售可行性限制' };
const emptyEvidence = (): GardenEvidence => ({ verified: false, conclusion: '', sources: [] });
export function editEvidenceSource(dimensions: Dimensions, key: Dimension, index: number, patch: Partial<Source>): Dimensions {
 const evidence = dimensions[key] ?? emptyEvidence();
 if (!evidence.sources[index]) throw new RangeError('来源不存在');
 return {...dimensions, [key]: {...evidence, verified: false, sources: evidence.sources.map((source, i) => i === index ? {...source, ...patch} : {...source})}};
}
export function appendEvidenceSource(dimensions: Dimensions, key: Dimension): Dimensions {
 const evidence = dimensions[key] ?? emptyEvidence();
 if (evidence.sources.length >= 20) throw new RangeError('每个维度最多20条来源');
 return {...dimensions, [key]: {...evidence, verified: false, sources: [...evidence.sources, { reference: '', date: '', kind: 'quote' }]}};
}
export function removeEvidenceSource(dimensions: Dimensions, key: Dimension, index: number): Dimensions {
 const evidence = dimensions[key] ?? emptyEvidence();
 return {...dimensions, [key]: {...evidence, verified: false, sources: evidence.sources.filter((_, i) => i !== index)}};
}
export function reviewInputIssues(draft: {status: GardenOpportunityRecord['status']; dimensions: Dimensions; confirmed: boolean; salesBlocked: boolean; reason: string; rejectionBasis: 'market' | 'sales_barrier'; asOf?: string}): string[] {
 if (draft.status === 'observation' || draft.status === 'pending_verification') return [];
 const issues: string[] = [];
 const asOf=draft.asOf??new Intl.DateTimeFormat('en-CA',{timeZone:'America/Los_Angeles',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const valid = (key: Dimension) => { const e = draft.dimensions[key]; return e?.verified && e.conclusion.trim() && e.sources.length > 0 && e.sources.every(s => economicSourceValid(s,asOf)); };
 if (!draft.confirmed) issues.push('需人工确认当前版本');
 if (draft.status === 'worth_validating') {
  for (const key of MARKET_DIMENSIONS) if (!valid(key)) issues.push(`${labels[key]}需完整且已核验的证据和来源`);
  if (draft.salesBlocked) issues.push('销售可行性障碍仍待确认');
 } else {
  if (!draft.reason.trim()) issues.push('需填写暂不建议原因');
  if (draft.rejectionBasis === 'sales_barrier') { if (!draft.salesBlocked || !valid('risk')) issues.push('需已核验的销售障碍证据'); }
  else if (!valid('demand') && !valid('competition')) issues.push('需需求或竞争证据支持暂不建议');
 }
 return issues;
}
