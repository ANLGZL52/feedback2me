#!/usr/bin/env node
// Observability V4/V5 — incident DELIVERY (transport + runner). Consumes the pure
// decisions from incident-actions.mjs and applies them through a swappable transport
// (GitHub Issues here; Slack/email adapters can be added without touching the engine).
//
// SAFETY: real GitHub writes require BOTH OPS_INCIDENT_DELIVERY_ENABLED=true AND
// not OPS_ALERT_DRY_RUN. Defaults => DRY_RUN => ZERO GitHub mutations. Every payload
// is validated (validateIssuePayload) before any send; a hit blocks the send.
//
// DEDUP DURABILITY (V5): local incident-state.json is seeded from the previous run's
// artifact (see ops-health.yml), AND — as an authoritative fallback against lost local
// state — before any CREATE the transport looks up an existing OPEN issue with the
// stable title `[OPS][CRITICAL] <CODE>` and reuses it. Two independent guards against
// duplicate issues. FAIL-SAFE: transport errors never crash the run or suppress
// evidence; they surface as incident.delivery.transport_error + INCIDENT_DELIVERY_FAILED.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { computeIncidentActions, deliveryMode, willWriteFor, renderIssueBody, issueTitle, issueLabels, validateIssuePayload, parseIncidentState, computeDeliveryHealth, INCIDENT_STATE_SCHEMA } from './incident-actions.mjs';

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
          // Label hardening (Phase 12): try WITH controlled labels; if the create fails
          // for a label reason (missing label + no permission to create it), retry WITHOUT
          // labels. Safe from duplicates — a failed create opens no issue. Never retry an
          // unsafe payload (already blocked above).
          try {
            const out = gh(['issue', 'create', '--title', title, '--body', body, '--label', issueLabels(inc).join(',')]);
            const m = out && out.match(/\/issues\/(\d+)/); return { ok: true, issueNumber: m ? Number(m[1]) : null };
          } catch (le) {
            if (!/label/i.test(le.message)) throw le;
            console.log(`[incident] label create failed for ${inc.incidentId} — retrying without labels`);
            const out = gh(['issue', 'create', '--title', title, '--body', body]);
            const m = out && out.match(/\/issues\/(\d+)/); return { ok: true, issueNumber: m ? Number(m[1]) : null, labelsDropped: true };
          }
        }
        if (action.action === 'REOPEN' && inc.issueNumber) { gh(['issue', 'reopen', String(inc.issueNumber)]); gh(['issue', 'comment', String(inc.issueNumber), '--body', `Re-fired${inc.flapping ? ' (FLAPPING)' : ''} at ${inc.lastObservedAt}.\n\n${body}`]); return { ok: true, issueNumber: inc.issueNumber }; }
        if (action.action === 'UPDATE' && inc.issueNumber) { gh(['issue', 'comment', String(inc.issueNumber), '--body', `Still active (${action.reason}) at ${inc.lastObservedAt}. Duration ${Math.round((inc.durationMs || 0) / 60000)} min.`]); return { ok: true, issueNumber: inc.issueNumber }; }
        if (action.action === 'RESOLVE' && inc.issueNumber) { gh(['issue', 'comment', String(inc.issueNumber), '--body', body]); gh(['issue', 'close', String(inc.issueNumber)]); return { ok: true, issueNumber: inc.issueNumber }; }
        return { ok: true }; // NONE or missing issue number — nothing to do
      } catch (e) { console.log(`[incident] transport error for ${inc.incidentId}: ${e.message}`); return { ok: false, error: e.message }; }
    },
  };
}

// Phase 9 — GitHub-side dedup fallback. Find an OPEN issue with the exact stable title.
// Best-effort: any failure returns null (caller then proceeds as if none existed). The
// exact-title match avoids reusing a superset/substring issue.
export function findOpenIssueNumber(gh, code) {
  try {
    const title = `[OPS][CRITICAL] ${code}`;
    const out = gh(['issue', 'list', '--state', 'open', '--label', 'ops', '--search', `in:title "${title}"`, '--json', 'number,title', '--limit', '20']);
    const list = JSON.parse(out || '[]');
    const hit = list.find((i) => i.title === title);
    return hit ? Number(hit.number) : null;
  } catch (e) { console.log(`[incident] issue lookup failed for ${code}: ${e.message}`); return null; }
}

// Safe, low-cardinality delivery event (Phase 12). No Issue body / raw payload / PII.
const ev = (event, a, inc, extra = {}) => ({ event, code: a.code, domain: a.domain, action: a.action, ...extra, issueNumber: inc && inc.issueNumber != null ? inc.issueNumber : null, ts: new Date().toISOString() });

/**
 * LIVE delivery. Applies write-actions through the adapter with a GitHub-side dedup
 * lookup before CREATE. Returns {events, failures}. Never throws.
 */
export function deliverLive({ actions, incidents, ctx, gh, adapter }) {
  const events = [];
  let failures = 0, dedupFallbackUsed = false;
  for (const a of actions) {
    if (a.action === 'NONE') continue; // rate-limit safety: NONE actions make ZERO gh calls
    const inc = incidents.find((i) => i.incidentId === a.incidentId);
    if (!inc) continue;
    events.push(ev('incident.delivery.attempted', a, inc));
    try {
      let action = a;
      // Dedup fallback: never CREATE if an OPEN issue with this identity already exists.
      // Called ONLY when an action actually needs a write (rate-limit safety) — never on a
      // healthy run with no actions.
      if (a.action === 'CREATE' || (!inc.issueNumber && (a.action === 'UPDATE' || a.action === 'REOPEN' || a.action === 'RESOLVE'))) {
        const existing = findOpenIssueNumber(gh, inc.code);
        if (existing) { inc.issueNumber = existing; dedupFallbackUsed = true; if (a.action === 'CREATE') action = { ...a, action: 'UPDATE', reason: 'reused_existing_issue' }; }
        else if (a.action === 'RESOLVE') { events.push(ev('incident.delivery.resolved', a, inc, { result: 'no_open_issue' })); continue; } // nothing to close
      }
      const res = adapter.apply(action, inc, ctx);
      if (res.rejected) { failures++; events.push(ev('incident.delivery.rejected_payload', a, inc, { result: res.code })); continue; }
      if (!res.ok) { failures++; events.push(ev('incident.delivery.transport_error', a, inc, { result: res.error || 'unknown' })); continue; }
      if (res.issueNumber && !inc.issueNumber) inc.issueNumber = res.issueNumber;
      const map = { CREATE: 'incident.delivery.created', REOPEN: 'incident.delivery.reopened', UPDATE: 'incident.delivery.updated', RESOLVE: 'incident.delivery.resolved' };
      events.push(ev(map[action.action] || 'incident.delivery.updated', a, inc, { result: 'ok', labelsDropped: res.labelsDropped || undefined }));
    } catch (e) { failures++; events.push(ev('incident.delivery.transport_error', a, inc, { result: e.message })); }
  }
  return { events, failures, dedupFallbackUsed };
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
  // Fail-safe, schema-versioned state read (Phases 7/8). UNTRUSTED/missing state drops
  // to empty prevIncidents and leans on the GitHub-side lookup fallback for dedup.
  const parsed = parseIncidentState(existsSync(stateP) ? readFileSync(stateP, 'utf8') : null);
  const prevIncidents = parsed.incidents;
  const seedStatus = process.env.OPS_STATE_SEED_STATUS || (existsSync(stateP) ? 'present' : 'missing');
  const seedSourceRun = process.env.OPS_STATE_SEED_SOURCE_RUN || null;
  if (parsed.stateTrust !== 'OK') console.log(`[incident] incident-state trust=${parsed.stateTrust} (${parsed.reason}) — dedup falls back to GitHub lookup`);

  const { incidents, actions } = computeIncidentActions({ alerts: health.alerts || [], prevIncidents, config: slo, now, deployment: health.deploymentContext || null, gateStatus: health.productReleaseGate && health.productReleaseGate.status });

  const dryRun = String(process.env.OPS_ALERT_DRY_RUN || 'true') !== 'false'; // default DRY-RUN
  const enabled = String(process.env.OPS_INCIDENT_DELIVERY_ENABLED || 'false') === 'true'; // default OFF
  const mode = deliveryMode(enabled, dryRun);
  const runUrl = process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY && process.env.GITHUB_RUN_ID
    ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}` : null;
  const ctx = { currentRuntimeHealth: health.currentRuntimeHealth, productReleaseGate: health.productReleaseGate && health.productReleaseGate.status, runUrl };

  const plan = actions.map((a) => ({ ...a, willWrite: willWriteFor(mode, a.action) }));
  console.log(`[incident] mode=${mode} enabled=${enabled} dryRun=${dryRun} actions=${JSON.stringify(actions.map((a) => a.action + ':' + a.incidentId))}`);

  const actionsNeeded = actions.filter((a) => a.action !== 'NONE').length;
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  const write = (extra = {}, dedupUsed = false, events = [], failures = 0) => {
    writeFileSync(stateP, JSON.stringify({ schemaVersion: INCIDENT_STATE_SCHEMA, generatedAt: new Date(now).toISOString(), incidents }, null, 2));
    const deliveryHealth = computeDeliveryHealth({ mode, actionsNeeded, events, failures, stateTrust: parsed.stateTrust, seedStatus, dedupFallbackUsed: dedupUsed, now });
    deliveryHealth.stateSeedSourceRun = seedSourceRun;
    writeFileSync(join(dir, 'incident-actions.json'), JSON.stringify({ generatedAt: new Date(now).toISOString(), mode, plan, deliveryHealth, ...extra }, null, 2));
    if (health.trends) writeFileSync(join(dir, 'trend.json'), JSON.stringify({ generatedAt: new Date(now).toISOString(), trends: health.trends }, null, 2));
  };

  if (mode !== 'LIVE') {
    write({ deliveryStatus: mode, deliveryEvents: [], deliveryFailures: 0 });
    console.log(`[incident] no GitHub writes (${mode}). Planned:`, plan.filter((p) => p.action !== 'NONE').map((p) => p.action + ' ' + p.code));
    return;
  }

  // LIVE delivery (enabled + not dry-run). Best-effort + fail-safe: a transport failure
  // must NOT crash the run or suppress evidence — it surfaces as INCIDENT_DELIVERY_FAILED
  // (NOT re-delivered through the same broken transport — Phase 10, no recursive alerting).
  let events = [], failures = 0, dedupUsed = false, deliveryStatus = 'LIVE_OK';
  try {
    const adapter = githubIssueAdapter((args) => execFileSync('gh', args, { cwd: REPO, encoding: 'utf8' }));
    const gh = (args) => execFileSync('gh', args, { cwd: REPO, encoding: 'utf8' });
    const res = deliverLive({ actions, incidents, ctx, gh, adapter });
    events = res.events; failures = res.failures; dedupUsed = res.dedupFallbackUsed;
    if (failures > 0) deliveryStatus = 'INCIDENT_DELIVERY_FAILED';
  } catch (e) {
    deliveryStatus = 'INCIDENT_DELIVERY_FAILED';
    console.log(`[incident] LIVE delivery fatal (contained): ${e.message}`);
  }
  write({ deliveryStatus, deliveryEvents: events, deliveryFailures: failures }, dedupUsed, events, failures);
  console.log(`[incident] LIVE delivery complete: status=${deliveryStatus} failures=${failures} events=${events.length}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
