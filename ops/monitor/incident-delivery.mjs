#!/usr/bin/env node
// Observability V4 — incident DELIVERY (transport + runner). Consumes the pure
// decisions from incident-actions.mjs and applies them through a swappable transport
// (GitHub Issues here; Slack/email adapters can be added without touching the engine).
// SAFETY: real GitHub writes require BOTH OPS_INCIDENT_DELIVERY_ENABLED=true AND
// not OPS_ALERT_DRY_RUN. Defaults => DRY_RUN => ZERO GitHub mutations. Every payload
// is validated (validateIssuePayload) before any send; a hit blocks the send.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { computeIncidentActions, deliveryMode, willWriteFor, renderIssueBody, issueTitle, issueLabels, validateIssuePayload } from './incident-actions.mjs';

// GitHub Issue transport adapter. `gh` = injectable command runner (real execFileSync
// in prod, a stub in tests). Returns {ok, issueNumber?, rejected?, code?} — never throws.
export function githubIssueAdapter(gh) {
  return {
    apply(action, inc, ctx) {
      const title = issueTitle(inc);
      const body = action.action === 'RESOLVE'
        ? `Resolved at ${inc.resolvedAt} (duration ${Math.round((inc.durationMs || 0) / 60000)} min). Clear for the required stability window.\n\n${renderIssueBody(inc, ctx)}`
        : renderIssueBody(inc, ctx);
      const check = validateIssuePayload(title, body);
      if (!check.safe) { console.log(`[incident] ${check.code}: ${check.violations.join(',')} — send BLOCKED for ${inc.incidentId}`); return { ok: false, rejected: true, code: check.code }; }
      try {
        if (action.action === 'CREATE') {
          const out = gh(['issue', 'create', '--title', title, '--body', body, '--label', issueLabels(inc).join(',')]);
          const m = out && out.match(/\/issues\/(\d+)/); return { ok: true, issueNumber: m ? Number(m[1]) : null };
        }
        if (action.action === 'REOPEN' && inc.issueNumber) { gh(['issue', 'reopen', String(inc.issueNumber)]); gh(['issue', 'comment', String(inc.issueNumber), '--body', `Re-fired${inc.flapping ? ' (FLAPPING)' : ''} at ${inc.lastObservedAt}.\n\n${body}`]); return { ok: true, issueNumber: inc.issueNumber }; }
        if (action.action === 'UPDATE' && inc.issueNumber) { gh(['issue', 'comment', String(inc.issueNumber), '--body', `Still active (${action.reason}) at ${inc.lastObservedAt}. Duration ${Math.round((inc.durationMs || 0) / 60000)} min.`]); return { ok: true, issueNumber: inc.issueNumber }; }
        if (action.action === 'RESOLVE' && inc.issueNumber) { gh(['issue', 'comment', String(inc.issueNumber), '--body', body]); gh(['issue', 'close', String(inc.issueNumber)]); return { ok: true, issueNumber: inc.issueNumber }; }
        return { ok: true }; // NONE or missing issue number — nothing to do
      } catch (e) { console.log(`[incident] transport error for ${inc.incidentId}: ${e.message}`); return { ok: false, error: e.message }; }
    },
  };
}

function main() {
  const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const slo = JSON.parse(readFileSync(join(REPO, 'ops', 'observability-slo.json'), 'utf8'));
  const healthP = join(REPO, 'ops-status', 'runtime-health.json');
  if (!existsSync(healthP)) { console.log('[incident] no runtime-health.json — run evaluate-runtime first'); return; }
  const health = JSON.parse(readFileSync(healthP, 'utf8'));
  const now = Date.now();
  const dir = join(REPO, 'ops-status');
  const stateP = join(dir, 'incident-state.json');
  const prevIncidents = existsSync(stateP) ? (JSON.parse(readFileSync(stateP, 'utf8')).incidents || []) : [];

  const { incidents, actions } = computeIncidentActions({ alerts: health.alerts || [], prevIncidents, config: slo, now, deployment: health.deploymentContext || null, gateStatus: health.productReleaseGate && health.productReleaseGate.status });

  const dryRun = String(process.env.OPS_ALERT_DRY_RUN || 'true') !== 'false'; // default DRY-RUN
  const enabled = String(process.env.OPS_INCIDENT_DELIVERY_ENABLED || 'false') === 'true'; // default OFF
  const mode = deliveryMode(enabled, dryRun);
  const runUrl = process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY && process.env.GITHUB_RUN_ID
    ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}` : null;
  const ctx = { currentRuntimeHealth: health.currentRuntimeHealth, productReleaseGate: health.productReleaseGate && health.productReleaseGate.status, runUrl };

  const plan = actions.map((a) => ({ ...a, willWrite: willWriteFor(mode, a.action) }));
  console.log(`[incident] mode=${mode} enabled=${enabled} dryRun=${dryRun} actions=${JSON.stringify(actions.map((a) => a.action + ':' + a.incidentId))}`);

  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  const write = () => writeFileSync(stateP, JSON.stringify({ generatedAt: new Date(now).toISOString(), incidents }, null, 2));
  write();
  writeFileSync(join(dir, 'incident-actions.json'), JSON.stringify({ generatedAt: new Date(now).toISOString(), mode, plan }, null, 2));
  if (health.trends) writeFileSync(join(dir, 'trend.json'), JSON.stringify({ generatedAt: new Date(now).toISOString(), trends: health.trends }, null, 2));

  if (mode !== 'LIVE') { console.log(`[incident] no GitHub writes (${mode}). Planned:`, plan.filter((p) => p.action !== 'NONE').map((p) => p.action + ' ' + p.code)); return; }

  // LIVE delivery (only reached with enabled+not-dry-run). Best-effort; never throws up.
  const adapter = githubIssueAdapter((args) => execFileSync('gh', args, { cwd: REPO, encoding: 'utf8' }));
  for (const a of actions) {
    if (a.action === 'NONE') continue;
    const inc = incidents.find((i) => i.incidentId === a.incidentId);
    if (!inc) continue;
    const res = adapter.apply(a, inc, ctx);
    if (res.ok && res.issueNumber && !inc.issueNumber) inc.issueNumber = res.issueNumber;
  }
  write(); // persist any new issue numbers
  console.log('[incident] LIVE delivery complete.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
