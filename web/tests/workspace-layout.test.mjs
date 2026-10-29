import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../app/', import.meta.url);
const source = async (path) => readFile(new URL(path, root), 'utf8');

test('shared command-center primitives exist with evidence and action regions', async () => {
  const names = ['WorkspaceShell.tsx', 'DecisionHero.tsx', 'TrendPanel.tsx', 'EvidenceRail.tsx', 'ActionDock.tsx', 'TimelinePanel.tsx'];
  const files = await Promise.all(names.map((name) => source(`components/${name}`)));
  for (const text of files) {
    assert.match(text, /export function/);
    assert.match(text, /aria-label|role=/);
  }
});

test('primary page groups use the structural workspace regions', async () => {
  const pages = await Promise.all([
    source('page.tsx'),
    source('market/page.tsx'),
    source('products/page.tsx'),
    source('reports/page.tsx'),
    source('analysis/page.tsx'),
    source('garden/opportunities/page.tsx'),
  ]);
  for (const text of pages) assert.match(text, /WorkspaceShell|DecisionHero|workspaceGrid/);
});

test('workspace CSS defines desktop three-column and mobile action layouts', async () => {
  const css = await readFile(new URL('../app/v2.css', import.meta.url), 'utf8');
  assert.match(css, /workspaceGrid/);
  assert.match(css, /workspaceEvidence/);
  assert.match(css, /workspaceActionDock/);
  assert.match(css, /@media\s*\(max-width:\s*700px\)/);
});
