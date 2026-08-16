#!/usr/bin/env node
// Ops alerting (Phase 24) — free-tier, GitHub-native. Reads ops-status/latest.json
// and opens/updates a single tracking GitHub issue ONLY when there is a P0
// release-blocker or a DOWN component (never the steady-state P1s -> no spam).
// Requires `gh` + issues:write. Emits NO PII/secret. Safe to run with `|| true`.
import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const p = join(REPO, 'ops-status', 'latest.json');
if (!existsSync(p)) { console.log('[alert] no snapshot'); process.exit(0); }
const s = JSON.parse(readFileSync(p, 'utf8'));

const p0 = (s.blockers || []).filter((b) => b.releaseBlocking && b.severity === 'P0');
const down = Object.entries(s.components || {}).filter(([, c]) => c.status === 'DOWN').map(([id]) => id);
const openInc = (s.incidents || []).filter((i) => i.status === 'OPEN');

if (!p0.length && !down.length) { console.log('[alert] no P0/DOWN — no alert (P1s are steady-state, not alerted)'); process.exit(0); }

const gh = (args) => execFileSync('gh', args, { cwd: REPO, encoding: 'utf8' });
const title = `[ops-alert] P0/DOWN detected (${(s.generatedAt || '').slice(0, 10)})`;
const body = [
  `Automated ops alert — overall **${s.overall}**, release **${s.release || '?'}**, build **${s.build ?? '?'}**.`,
  p0.length ? `\n**P0 blockers:** ${p0.map((b) => b.id).join(', ')}` : '',
  down.length ? `\n**DOWN components:** ${down.join(', ')}` : '',
  openInc.length ? `\n**Open incidents:** ${openInc.map((i) => i.componentId).join(', ')}` : '',
  `\n\n_No PII/secret. Source: ops-status/latest.json. Resolve, then this issue auto-quiets (no new P0/DOWN)._`,
].filter(Boolean).join('');

try {
  const existing = JSON.parse(gh(['issue', 'list', '--label', 'ops-alert', '--state', 'open', '--json', 'number', '--limit', '1']) || '[]');
  if (existing.length) {
    gh(['issue', 'comment', String(existing[0].number), '--body', body]);
    console.log('[alert] commented on #' + existing[0].number);
  } else {
    // ensure the label exists (ignore error if it already does), then create
    try { gh(['label', 'create', 'ops-alert', '--color', 'B60205', '--description', 'Automated ops P0/DOWN alert']); } catch {}
    gh(['issue', 'create', '--title', title, '--label', 'ops-alert', '--body', body]);
    console.log('[alert] opened new ops-alert issue');
  }
} catch (e) {
  console.log('[alert] gh unavailable or issues disabled: ' + e.message);
}
