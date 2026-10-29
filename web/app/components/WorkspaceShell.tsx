import { MarketContext } from './MarketContext';
import type { MarketContext as MarketContextValue } from '@/lib/market-context';

export function WorkspaceShell({
  children,
  context,
  marketDate,
  validMarketDates,
  page,
  eyebrow,
  title,
  description,
  evidence,
  actions,
}: {
  children: React.ReactNode;
  context: MarketContextValue;
  marketDate: string;
  validMarketDates?: string[];
  page: Parameters<typeof MarketContext>[0]['page'];
  eyebrow?: string;
  title: string;
  description: string;
  evidence?: React.ReactNode;
  actions?: React.ReactNode;
}) {
  return <>
    <MarketContext marketDate={marketDate} validMarketDates={validMarketDates} context={context} page={page} />
    <section className="workspaceGrid" aria-label={`${title}工作区`}>
      <aside className="workspaceContext"><p className="pageEyebrow">{eyebrow ?? '证据优先指挥台'}</p><h1>{title}</h1><p>{description}</p>{evidence && <div className="workspaceEvidence">{evidence}</div>}</aside>
      <main className="workspaceMain">{children}</main>
      <aside className="workspaceActions"><div className="workspaceEvidenceRail">{evidence}</div>{actions && <div className="workspaceActionDock">{actions}</div>}</aside>
    </section>
  </>;
}
