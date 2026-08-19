#!/usr/bin/env node
// Observability V4 — Ops Console (Phase 2), GitHub Actions step summary (Phase 3),
// daily digest foundation (Phase 13). PURE renderers + a runner. Reads the artifacts
// produced by evaluate-runtime (runtime-health.json) and incident-delivery
// (incidents.json, incident-plan.json). Metadata only — no PII/secrets ever.
import { readFileSync, writeFileSync, existsSync, appendFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { RUNBOOK_SECTIONS } from './incident-actions.mjs';

const TREND_GLYPH = { IMPROVING: '↓ improving', DEGRADING: '↑ DEGRADING', STABLE: '→ stable', INSUFFICIENT_DATA: '· n/a' };
const STATUS_GLYPH = { HEALTHY: '🟢', IDLE: '🟢', UNKNOWN: '⚪', DEGRADED: '🟡', UNHEALTHY: '🔴', DOWN: '🔴' };
const g = (s) => (STATUS_GLYPH[s] || '⚪') + ' ' + s;

/** The private Ops Console — the full operational picture for the owner. */
export function renderConsole(health, incidents = [], plan = null, digest = null) {
  const L = [];
  const gate = health.productReleaseGate || {};
  L.push(`# 🛰️ Feedback2Me Ops Console`);
  L.push('');
  L.push(`Generated ${health.generatedAt} · window ${health.window?.lookbackHours}h · ${health.window?.events} events`);
  L.push('');
  L.push('| Dimension | Status |');
  L.push('|---|---|');
  L.push(`| Observability Platform | **${health.observabilityPlatformStatus}** |`);
  L.push(`| Runtime Validation | **${health.runtimeValidationStatus}** |`);
  L.push(`| Product Release Gate | **${gate.status}** |`);
  L.push(`| Current Runtime | ${g(health.currentRuntimeHealth)} |`);
  L.push('');

  // Domains + trend.
  const d = health.domains || {}, t = health.trends || {};
  L.push('## Domains');
  L.push('| Domain | Status | Trend signal |');
  L.push('|---|---|---|');
  const trendFor = { IAP: t.iapVerifyFailures, OPENAI: t.openaiFailures, RAILWAY: t.railway5xx, POSTGRES: null, COLLECTOR: t.collectorAgeMin, SECURITY: null };
  for (const [k, v] of Object.entries(d)) {
    const tr = trendFor[k] ? ` (${TREND_GLYPH[trendFor[k]] || trendFor[k]})` : '';
    L.push(`| ${k} | ${g(v.status)} | ${trendFor[k] ? (TREND_GLYPH[trendFor[k]] || trendFor[k]) : '—'} |`);
  }
  L.push('');

  // Per-domain metric detail (concise — no raw logs).
  const m = (k) => (d[k] && d[k].metrics) || {};
  const iap = m('IAP'), oa = m('OPENAI'), rw = m('RAILWAY'), pg = m('POSTGRES'), col = m('COLLECTOR');
  const ic = iap.counts || {};
  L.push('## Metrics (window)');
  L.push(`- **IAP** — verify total ${ic.verifyAttempts ?? (ic.success != null ? (ic.success + (ic.rejected || 0) + (ic.transientFailure || 0) + (ic.error || 0)) : '—')}, success ${ic.success ?? '—'}, rejected ${ic.rejected ?? '—'}, transient ${ic.transientFailure ?? '—'}, error ${ic.error ?? '—'}, grants ${ic.granted ?? '—'}, replays ${ic.replay ?? '—'}, p95 ${iap.latency?.p95 ?? iap.latencyMsP95 ?? '—'}ms · money-safety ${d.IAP ? d.IAP.status : '—'} · Real E2E ${health.validationEvidence?.realIapE2E || '—'}`);
  L.push(`- **OpenAI** — req ${oa.requests ?? '—'}, completed ${oa.completed ?? '—'}, failed ${oa.failed ?? '—'}, p95 ${oa.latencyP95Ms ?? '—'}ms, avg tokens ${oa.avgTotalTokens ?? '—'}`);
  L.push(`- **Railway** — req ${rw.requests ?? '—'} (2xx ${rw['2xx'] ?? '—'}, 4xx ${rw['4xx'] ?? '—'}, 5xx ${rw['5xx'] ?? '—'})${(rw.requests ?? 0) === 0 ? ' · NO_TRAFFIC' : ''}`);
  L.push(`- **Postgres** — probe ${pg.probe ?? '—'}, consecutive failures ${pg.consecutiveFailures ?? '—'}`);
  L.push(`- **Collector** — last ${col.lastEventAt || '—'} (${col.ageMinutes ?? '—'} min), providers ${col.providersSucceeded ?? '—'}/${col.providersAttempted ?? '—'}`);
  L.push('');

  // Active incidents (OPEN) + what delivery WOULD do.
  const open = incidents.filter((i) => i.state === 'OPEN');
  L.push(`## Active incidents (${open.length})`);
  if (!open.length) L.push('_None — no CRITICAL alert is currently open._');
  else {
    L.push('| Incident | Domain | Started | Duration | Issue | Runbook |');
    L.push('|---|---|---|---|---|---|');
    for (const i of open) L.push(`| \`${i.code}\`${i.flapping ? ' ⚡FLAPPING' : ''} | ${i.domain} | ${i.startedAt} | ${Math.round((i.durationMs || 0) / 60000)}m | ${i.issueNumber ? '#' + i.issueNumber : '—'} | ${i.runbookSection || '—'} |`);
  }
  L.push('');

  if (plan) {
    const live = plan.mode === 'LIVE';
    const dh = plan.deliveryHealth || {};
    const lastEvent = (plan.deliveryEvents || []).slice(-1)[0];
    L.push(`## Incident Delivery`);
    L.push(`- **Mode:** ${live ? 'LIVE' : plan.mode}  ·  **Health:** ${dh.deliveryHealth || (live ? 'IDLE' : 'n/a')}  ·  **Dry run:** ${live ? 'OFF' : 'ON'}`);
    L.push(`- **State seed:** ${dh.stateSeedStatus || 'unknown'}${dh.stateSeedSourceRun ? ' (run ' + dh.stateSeedSourceRun + ')' : ''}  ·  **State trust:** ${dh.stateTrust || 'OK'}  ·  **Dedup fallback used:** ${dh.dedupFallbackUsed ? 'yes' : 'no'}`);
    L.push(`- **Failures:** ${plan.deliveryFailures ?? 0} (transport ${dh.deliveryTransportErrors ?? 0}, payload-rejected ${dh.deliveryPayloadRejections ?? 0})  ·  **Delivery status:** ${plan.deliveryStatus || plan.mode}`);
    L.push(`- **Last action:** ${lastEvent ? `${lastEvent.event} \`${lastEvent.code}\`${lastEvent.issueNumber ? ' #' + lastEvent.issueNumber : ''} (${lastEvent.result || '—'})` : 'none this run'}`);
    const acts = (plan.plan || []).filter((p) => p.action !== 'NONE');
    if (!acts.length) L.push('- _No delivery actions this run._');
    else { L.push('', '| Action | Incident | Wrote? | Reason |'); L.push('|---|---|---|---|'); for (const p of acts) L.push(`| **${p.action}** | \`${p.code}\` | ${p.willWrite ? 'yes' : 'no (suppressed)'} | ${p.reason || '—'} |`); }
    if (!live) L.push(`\n> Delivery is **${plan.mode}** — zero GitHub writes.`);
    else if ((plan.deliveryFailures ?? 0) > 0) L.push(`\n> ⚠️ **INCIDENT_DELIVERY_FAILED** — ${plan.deliveryFailures} action(s) failed; monitoring evidence was still produced (best-effort; NOT re-delivered through the broken transport).`);
    L.push('');
  }

  if (digest) {
    const dd = digest.data || {}, dst = digest.state || {}, sch = dd.schedule || {}, dv = digest.delivery || {};
    const sent = dv.delivered ? 1 : 0;
    L.push(`## Daily Digest`);
    L.push(`- **Generation:** ${dd.generatedAt ? 'HEALTHY' : 'UNKNOWN'} (${dd.generatedAt || dst.lastDigestGeneratedAt || '—'})`);
    L.push(`- **Delivery channel:** ${dv.channel ? dv.channel.toUpperCase() : 'SLACK'}  ·  **Delivery mode:** ${dv.mode || digest.deliveryMode || 'DISABLED'}  ·  **Delivery health:** ${dv.health || 'IDLE'}`);
    L.push(`- **Current window:** ${sch.window || dst.lastDigestWindow || '—'}  ·  **Due:** ${sch.due ? 'yes' : 'no'} (${sch.reason || '—'})`);
    L.push(`- **Last delivery:** ${dst.lastDigestDeliveredAt || 'never'}  ·  **Last result:** ${(dv.event && dv.event.result) || dv.health || '—'}${dv.event && dv.event.statusCode ? ' (' + dv.event.statusCode + ')' : ''}  ·  **Messages sent this run:** ${sent}`);
    L.push(`- **Next eligibility:** ${sch.nextEligibleAt || '—'}${dv.health === 'NOT_CONFIGURED' ? '  ·  ⚠️ **OPS_SLACK_WEBHOOK_URL not configured** (0 messages until set)' : ''}`);
    L.push('');
  }

  // Resolved incidents (flapping-memory window).
  const resolved = incidents.filter((i) => i.state === 'RESOLVED');
  L.push(`## Resolved incidents (${resolved.length})`);
  if (!resolved.length) L.push('_None in the recent window._');
  else for (const i of resolved) L.push(`- \`${i.code}\` (${i.domain}) — resolved ${i.resolvedAt}, duration ${Math.round((i.durationMs || 0) / 60000)}m`);
  L.push('');

  // Deferred validations (honest, not-an-incident).
  if ((health.deferredValidations || []).length) {
    L.push('## Deferred validations');
    for (const v of health.deferredValidations) L.push(`- \`${v.id}\` — ${v.status} (${v.reason}); blocks product release: ${v.requiredForProductRelease}, blocks platform: ${v.requiredForObservabilityPlatform}`);
    L.push('');
  }

  // Trends.
  L.push('## Trends');
  const tt = health.trends || {};
  if (!Object.keys(tt).length) L.push('_No trend data._');
  else for (const [k, v] of Object.entries(tt)) L.push(`- ${k}: ${TREND_GLYPH[v] || v}`);
  L.push('');

  // Release gate.
  L.push('## Release gate');
  L.push(`- **${gate.status}** — blocking: ${(gate.blocking || []).map((c) => '`' + c + '`').join(', ') || 'none'}; warnings: ${(gate.warnings || []).map((c) => '`' + c + '`').join(', ') || 'none'}`);
  return L.join('\n');
}

/** Actionable GitHub Actions run summary ($GITHUB_STEP_SUMMARY). Owner-scannable at a glance. */
export function renderStepSummary(health, incidents = [], plan = null, digest = null) {
  const gate = health.productReleaseGate || {};
  const open = incidents.filter((i) => i.state === 'OPEN');
  const critical = (gate.blocking || []).length;
  const L = [];
  L.push(`## 🛰️ Ops — ${g(health.currentRuntimeHealth)} · gate **${gate.status}** · platform **${health.observabilityPlatformStatus}**`);
  L.push('');
  if ((gate.blocking || []).length) { L.push(`**🔴 RELEASE BLOCKING:** ${gate.blocking.map((c) => '`' + c + '`').join(', ')}`); L.push(''); }
  if ((gate.warnings || []).length) { L.push(`**🟡 Warnings:** ${gate.warnings.map((c) => '`' + c + '`').join(', ')}`); L.push(''); }
  if (open.length) {
    L.push(`### Active incidents (${open.length})`);
    for (const i of open) L.push(`- \`${i.code}\` (${i.domain}) — ${Math.round((i.durationMs || 0) / 60000)}m · runbook \`${i.runbookSection || RUNBOOK_SECTIONS[i.code] || '—'}\`${i.issueNumber ? ' · #' + i.issueNumber : ''}`);
    L.push('');
  }
  if (plan) {
    const live = plan.mode === 'LIVE';
    const dh = plan.deliveryHealth || {};
    const acts = (plan.plan || []).filter((p) => p.action !== 'NONE');
    const fails = plan.deliveryFailures ?? 0;
    L.push(`### Incident Delivery: **${live ? 'LIVE' : plan.mode}** / **${dh.deliveryHealth || (live ? 'IDLE' : 'n/a')}** · Active Critical: **${critical}** · ${acts.length} action(s)${fails ? `, ${fails} failure(s)` : ''}`);
    if (acts.length) for (const p of acts) L.push(`- **${p.action}** \`${p.code}\` → ${p.willWrite ? 'WRITE' : 'no write (' + plan.mode + ')'}`);
    else L.push(`- none${live ? ' (armed; runtime healthy → 0 issues written)' : ''}`);
    if (!live) L.push(`\n> Dry-run/disabled — **0 GitHub issues written**.`);
    else if (fails > 0) L.push(`\n> ⚠️ **INCIDENT_DELIVERY_FAILED** — ${fails} failed; evidence still produced (best-effort).`);
  }
  if (digest) {
    const sch = (digest.data && digest.data.schedule) || {};
    const dv = digest.delivery || {};
    const channel = (dv.channel || 'slack').toUpperCase();
    // Phase 18: SLACK / <state> — SENT | NOT_DUE | NOT_CONFIGURED | FAILED | DRY_RUN | DISABLED
    let state;
    if (dv.health === 'NOT_CONFIGURED') state = 'NOT_CONFIGURED';
    else if (dv.delivered) state = 'SENT';
    else if (dv.code === 'DIGEST_DELIVERY_FAILED' || dv.code === 'DIGEST_DELIVERY_PAYLOAD_REJECTED') state = 'FAILED';
    else if (dv.mode === 'DRY_RUN') state = 'DRY_RUN';
    else if (dv.mode === 'DISABLED') state = 'DISABLED';
    else state = sch.due ? 'DUE' : 'NOT_DUE';
    L.push(`### Daily Digest: **${channel} / ${state}** · window ${sch.window || '—'} · messages sent: ${dv.delivered ? 1 : 0}`);
  }
  return L.join('\n');
}

function main() {
  const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const rd = (p) => (existsSync(p) ? (() => { try { return JSON.parse(readFileSync(p, 'utf8')); } catch { return null; } })() : null);
  const health = rd(join(REPO, 'ops-status', 'runtime-health.json'));
  if (!health) { console.log('[console] no runtime-health.json'); return; }
  const incidents = (rd(join(REPO, 'ops-status', 'incident-state.json')) || {}).incidents || [];
  const plan = rd(join(REPO, 'ops-status', 'incident-actions.json'));
  // Digest artifacts are produced by digest.mjs (runs before this step).
  const digestData = rd(join(REPO, 'ops-status', 'daily-digest.json'));
  const digestState = rd(join(REPO, 'ops-status', 'digest-state.json'));
  const digestDelivery = rd(join(REPO, 'ops-status', 'digest-delivery.json'));
  const digest = digestData ? { data: digestData, state: digestState || {}, delivery: digestDelivery || {}, deliveryMode: (digestDelivery && digestDelivery.mode) || 'DISABLED' } : null;

  writeFileSync(join(REPO, 'ops-status', 'ops-console.md'), renderConsole(health, incidents, plan, digest));
  const summary = renderStepSummary(health, incidents, plan, digest);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary + '\n');
  console.log(summary);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
