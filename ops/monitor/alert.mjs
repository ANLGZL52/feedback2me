#!/usr/bin/env node
// Ops alerting (Phase 24 + live-only calibration) — free-tier, GitHub-native.
// Reads ops-status/latest.json and opens/updates a SINGLE tracking GitHub issue
// ONLY for real RUNTIME operational incidents:
//   - a live monitored component is DOWN, OR
//   - an OPEN incident exists (reconcileIncidents only opens these from live
//     component DOWN/DEGRADED transitions — never from release blockers).
// It DELIBERATELY ignores release-readiness signals (CI missing/stale P0s,
// journey UNKNOWN/not-verified, version-config/build-number/isPremium/ownership
// gates, static risks) — release readiness != a runtime outage. DEGRADED alone
// does NOT alert (dashboard-only); only a DEGRADED incident already escalated to
// severity P0 by a live check would. Emits NO PII/secret. Safe to run with `|| true`.
import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

/**
 * Pure alert decision (exported for tests). Runtime-only:
 *  - down: components whose live status === 'DOWN'
 *  - openIncidents: incidents with status === 'OPEN' (live-sourced by construction)
 * Release blockers (snapshot.blockers) are IGNORED here on purpose.
 */
export function decideAlert(snapshot) {
  const s = snapshot || {};
  const down = Object.entries(s.components || {})
    .filter(([, c]) => c && c.status === 'DOWN')
    .map(([id]) => id);
  const openInc = (s.incidents || []).filter((i) => i && i.status === 'OPEN');
  // A DEGRADED-only state never alerts; only an OPEN incident already at P0 counts.
  const p0Inc = openInc.filter((i) => i.severity === 'P0');
  const alert = down.length > 0 || openInc.length > 0;
  return {
    alert,
    down,
    openIncidentCount: openInc.length,
    p0IncidentCount: p0Inc.length,
    reasons: [
      ...down.map((id) => `component ${id} DOWN`),
      ...openInc.map((i) => `incident ${i.componentId || i.id} ${i.status}`),
    ],
  };
}

// ---- side-effecting runner (skipped when imported for tests) ----
function main() {
  const p = join(REPO, 'ops-status', 'latest.json');
  if (!existsSync(p)) { console.log('[alert] no snapshot'); return; }
  const s = JSON.parse(readFileSync(p, 'utf8'));
  const d = decideAlert(s);
  const gh = (args) => execFileSync('gh', args, { cwd: REPO, encoding: 'utf8' });

  // Find any existing open tracking issue (single, deduplicated).
  let existing = [];
  try {
    existing = JSON.parse(gh(['issue', 'list', '--label', 'ops-alert', '--state', 'open', '--json', 'number', '--limit', '1']) || '[]');
  } catch (e) { console.log('[alert] gh unavailable: ' + e.message); return; }

  if (!d.alert) {
    // No live runtime incident. RECOVERY: if a tracking issue is open, comment + close it.
    if (existing.length) {
      const n = String(existing[0].number);
      try {
        gh(['issue', 'comment', n, '--body', `Recovery: no live component is DOWN and no open runtime incident remains (overall **${s.overall}**, release ${s.release || '?'}). Auto-closing this ops-alert. Release-readiness blockers, if any, are tracked by the release gate, not here.`]);
        gh(['issue', 'close', n]);
        console.log('[alert] recovery — closed #' + n);
      } catch (e) { console.log('[alert] recovery close failed: ' + e.message); }
    } else {
      console.log('[alert] no live DOWN / open incident — no alert (release-readiness blockers are NOT runtime incidents)');
    }
    return;
  }

  // Live incident present.
  const title = `[ops-alert] live outage detected (${(s.generatedAt || '').slice(0, 10)})`;
  const body = [
    `RUNTIME incident — overall **${s.overall}**, release **${s.release || '?'}**, build **${s.build ?? '?'}**.`,
    d.down.length ? `\n**DOWN components:** ${d.down.join(', ')}` : '',
    d.openIncidentCount ? `\n**Open incidents:** ${d.openIncidentCount}${d.p0IncidentCount ? ` (P0: ${d.p0IncidentCount})` : ''}` : '',
    `\n\n_Live signals only (component DOWN / open incident). Release-readiness blockers are excluded by design. No PII/secret._`,
  ].filter(Boolean).join('');

  try {
    if (existing.length) {
      gh(['issue', 'comment', String(existing[0].number), '--body', body]);
      console.log('[alert] updated existing #' + existing[0].number);
    } else {
      try { gh(['label', 'create', 'ops-alert', '--color', 'B60205', '--description', 'Automated ops live-outage alert']); } catch {}
      gh(['issue', 'create', '--title', title, '--label', 'ops-alert', '--body', body]);
      console.log('[alert] opened new ops-alert issue');
    }
  } catch (e) { console.log('[alert] gh write failed: ' + e.message); }
}

// Only run side effects when invoked directly, not when imported by tests.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
