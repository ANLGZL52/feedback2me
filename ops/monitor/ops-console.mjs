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
export function renderConsole(health, incidents = [], plan = null) {
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
    L.push(`## Incident delivery plan — mode: **${plan.mode}**`);
    const acts = (plan.plan || []).filter((p) => p.action !== 'NONE');
    if (!acts.length) L.push('_No delivery actions this run._');
    else { L.push('| Action | Incident | Would write? | Reason |'); L.push('|---|---|---|---|'); for (const p of acts) L.push(`| **${p.action}** | \`${p.code}\` | ${p.willWrite ? 'yes' : 'NO (suppressed)'} | ${p.reason || '—'} |`); }
    if (plan.mode !== 'LIVE') L.push(`\n> Delivery is **${plan.mode}** — zero GitHub writes. Enable real issues only with owner approval (\`OPS_INCIDENT_DELIVERY_ENABLED=true\` + \`OPS_ALERT_DRY_RUN=false\`).`);
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
export function renderStepSummary(health, incidents = [], plan = null) {
  const gate = health.productReleaseGate || {};
  const open = incidents.filter((i) => i.state === 'OPEN');
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
    const acts = (plan.plan || []).filter((p) => p.action !== 'NONE');
    L.push(`### Incident delivery: **${plan.mode}** — ${acts.length} action(s)`);
    if (acts.length) for (const p of acts) L.push(`- **${p.action}** \`${p.code}\` → ${p.willWrite ? 'WRITE' : 'no write (' + plan.mode + ')'}`);
    else L.push('- none');
    if (plan.mode !== 'LIVE') L.push(`\n> Dry-run/disabled — **0 GitHub issues written**. Awaiting owner approval to enable real delivery.`);
  }
  return L.join('\n');
}

/** Daily digest foundation — artifact only, never delivered. */
export function renderDailyDigest(health, incidents = []) {
  const open = incidents.filter((i) => i.state === 'OPEN');
  const resolvedToday = incidents.filter((i) => i.state === 'RESOLVED');
  const L = [`# Ops daily digest (foundation)`, '', `Snapshot ${health.generatedAt}`, '',
    `- Runtime: **${health.currentRuntimeHealth}** · gate **${health.productReleaseGate?.status}** · platform **${health.observabilityPlatformStatus}**`,
    `- Open incidents: **${open.length}**${open.length ? ' — ' + open.map((i) => '`' + i.code + '`').join(', ') : ''}`,
    `- Recently resolved (flapping-memory window): **${resolvedToday.length}**`,
    `- Deferred validations: ${(health.deferredValidations || []).map((v) => '`' + v.id + '`').join(', ') || 'none'}`,
    '', '_Foundation artifact only — not delivered anywhere (no email/Slack/issue). Scheduled digest delivery is a future phase, owner-gated._'];
  return L.join('\n');
}

function main() {
  const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const rd = (p) => (existsSync(p) ? JSON.parse(readFileSync(p, 'utf8')) : null);
  const health = rd(join(REPO, 'ops-status', 'runtime-health.json'));
  if (!health) { console.log('[console] no runtime-health.json'); return; }
  const incidents = (rd(join(REPO, 'ops-status', 'incident-state.json')) || {}).incidents || [];
  const plan = rd(join(REPO, 'ops-status', 'incident-actions.json'));

  writeFileSync(join(REPO, 'ops-status', 'ops-console.md'), renderConsole(health, incidents, plan));
  writeFileSync(join(REPO, 'ops-status', 'daily-digest.md'), renderDailyDigest(health, incidents));
  const summary = renderStepSummary(health, incidents, plan);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary + '\n');
  console.log(summary);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
