#!/usr/bin/env node
// Observability V6 — daily digest. Rolling-24h operational summary as a markdown +
// JSON artifact, with a transport-independent delivery abstraction. EXTERNAL DELIVERY
// IS DISABLED in V6 (OPS_DIGEST_DELIVERY_ENABLED=false, OPS_DIGEST_DRY_RUN=true): this
// only renders exactly what WOULD be sent. Deterministic once-per-UTC-day eligibility so
// repeated 30-min runs never duplicate a send. No PII / no raw logs / no user content.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';

export const DIGEST_STATE_SCHEMA = 1;
export const DIGEST_HOUR_UTC = 7; // one canonical delivery window per UTC day, at/after 07:00 UTC
const DAY_MS = 86400000;
export const windowKey = (now) => new Date(now).toISOString().slice(0, 10); // 'YYYY-MM-DD' (UTC)

/**
 * Deterministic digest scheduling (Phases 19/20). Pure. `state` = persisted digest state.
 * due=true at most ONCE per UTC day: past the delivery hour AND not already delivered this
 * window. Repeated runs in the same window after a delivery return due=false.
 */
export function computeDigestSchedule(now, state = {}, hourUtc = DIGEST_HOUR_UTC) {
  const window = windowKey(now);
  const utcHour = new Date(now).getUTCHours();
  const deliveredThisWindow = state.lastDigestDeliveredWindow === window;
  let due = false, reason;
  if (deliveredThisWindow) { reason = 'already_delivered_this_window'; }
  else if (utcHour < hourUtc) { reason = 'before_delivery_window'; }
  else { due = true; reason = 'eligible'; }
  // next eligibility: today's hour if still upcoming, else tomorrow's hour.
  const base = new Date(now); base.setUTCMinutes(0, 0, 0);
  const todayAt = new Date(base); todayAt.setUTCHours(hourUtc);
  const next = (utcHour < hourUtc && !deliveredThisWindow) ? todayAt : new Date(todayAt.getTime() + DAY_MS);
  return { window, due, reason, nextEligibleAt: next.toISOString() };
}

const withinWindow = (iso, now, ms = DAY_MS) => { const t = Date.parse(iso); return Number.isFinite(t) && now - t <= ms && now - t >= -ms; };

/** Build the machine-readable digest (daily-digest.json). Pure. No PII. */
export function renderDigestData({ health, incidents = [], actions = null, schedule, now }) {
  const dom = health.domains || {};
  const ds = (k) => (dom[k] && dom[k].status) || 'UNKNOWN';
  const opened = incidents.filter((i) => withinWindow(i.startedAt, now));
  const resolved = incidents.filter((i) => i.resolvedAt && withinWindow(i.resolvedAt, now));
  const active = incidents.filter((i) => i.state === 'OPEN');
  const flapping = active.filter((i) => i.flapping);
  const dh = (actions && actions.deliveryHealth) || {};
  return {
    schemaVersion: DIGEST_STATE_SCHEMA,
    generatedAt: new Date(now).toISOString(),
    windowStart: new Date(now - DAY_MS).toISOString(),
    windowEnd: new Date(now).toISOString(),
    digestId: schedule ? schedule.window : windowKey(now),
    runtimeStatus: health.currentRuntimeHealth,
    observabilityPlatform: health.observabilityPlatformStatus,
    runtimeValidation: health.runtimeValidationStatus,
    releaseGate: (health.productReleaseGate || {}).status,
    deploymentContext: health.deploymentContext || null,
    incidentCounts: { opened: opened.length, resolved: resolved.length, active: active.length, flapping: flapping.length },
    activeIncidents: active.map((i) => ({ code: i.code, domain: i.domain, startedAt: i.startedAt, issueNumber: i.issueNumber ?? null, flapping: !!i.flapping })),
    domainHealth: { iap: ds('IAP'), openai: ds('OPENAI'), railway: ds('RAILWAY'), postgres: ds('POSTGRES'), collector: ds('COLLECTOR'), gcpWif: (health.collectorFreshness ? 'SEE_COLLECTOR' : 'UNKNOWN'), service: ds('SERVICE') },
    trends: health.trends || {},
    deliveryHealth: { mode: dh.deliveryMode || null, health: dh.deliveryHealth || null, failures: dh.deliveryFailuresWindow ?? 0, transportErrors: dh.deliveryTransportErrors ?? 0, payloadRejections: dh.deliveryPayloadRejections ?? 0 },
    deferredValidations: (health.deferredValidations || []).map((v) => ({ id: v.id, status: v.status })),
    realIapE2E: (health.validationEvidence || {}).realIapE2E || 'DEFERRED',
    schedule: schedule || null,
  };
}

/** Human digest markdown (daily-digest.md). Pure. No raw logs. */
export function renderDigest(d) {
  const t = d.trends || {}, ic = d.incidentCounts || {};
  const L = [`# Feedback2Me — Daily Ops Digest`, '', `Window: ${d.windowStart} → ${d.windowEnd} (rolling 24h, UTC)  ·  digest \`${d.digestId}\``, '',
    `## Overview`,
    `- Runtime: **${d.runtimeStatus}** · Platform: **${d.observabilityPlatform}** · Validation: **${d.runtimeValidation}** · Release gate: **${d.releaseGate}**`,
    `- Deploy: commit ${d.deploymentContext?.commit || '—'} · build ${d.deploymentContext?.build || '—'}`,
    `- Real IAP E2E: **${d.realIapE2E}**`,
    '', `## Incidents (24h)`,
    `- Opened: **${ic.opened}** · Resolved: **${ic.resolved}** · Active: **${ic.active}** · Flapping: **${ic.flapping}**`,
    ...(d.activeIncidents.length ? d.activeIncidents.map((i) => `  - \`${i.code}\` (${i.domain})${i.flapping ? ' ⚡FLAPPING' : ''}${i.issueNumber ? ' · #' + i.issueNumber : ''}`) : ['  - _none active_']),
    '', `## Incident delivery`,
    `- Mode: **${d.deliveryHealth.mode || 'n/a'}** · Health: **${d.deliveryHealth.health || 'n/a'}** · Failures: **${d.deliveryHealth.failures}** (transport ${d.deliveryHealth.transportErrors}, payload-rejected ${d.deliveryHealth.payloadRejections})`,
    '', `## Domain health`,
    `- IAP ${d.domainHealth.iap} · OpenAI ${d.domainHealth.openai} · Railway ${d.domainHealth.railway} · Postgres ${d.domainHealth.postgres} · Collector ${d.domainHealth.collector} · Service ${d.domainHealth.service}`,
    '', `## 24h trends`,
    ...(Object.keys(t).length ? Object.entries(t).map(([k, v]) => `- ${k}: ${v}`) : ['- _no trend data_']),
    '', `## Deferred validations`,
    ...(d.deferredValidations.length ? d.deferredValidations.map((v) => `- \`${v.id}\` — ${v.status}`) : ['- none']),
    '', `_Artifact only — no raw logs, no user data. External delivery is DISABLED in this milestone._`];
  return L.join('\n');
}

// ---- delivery abstraction (Phase 16) — transport-independent, no provider implemented ----
export function deliverDigest(adapter, data, { enabled = false, dryRun = true } = {}) {
  const subject = `Feedback2Me Ops Digest ${data.digestId} — ${data.runtimeStatus}`;
  const willSend = enabled && !dryRun;
  if (!willSend) return { delivered: false, mode: dryRun ? 'DRY_RUN' : (enabled ? 'READY' : 'DISABLED'), subject };
  try { const r = adapter && adapter.send ? adapter.send(subject, renderDigest(data)) : { ok: false }; return { delivered: !!(r && r.ok), mode: 'LIVE', subject }; }
  catch (e) { return { delivered: false, mode: 'LIVE', error: e.message, subject }; }
}
// Null adapter — records nothing external. Real email/Slack/Discord adapters plug in here.
export const nullDigestAdapter = { name: 'null', send: () => ({ ok: false, note: 'no digest transport configured' }) };

function main() {
  const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const dir = join(REPO, 'ops-status');
  const rd = (p) => (existsSync(p) ? (() => { try { return JSON.parse(readFileSync(p, 'utf8')); } catch { return null; } })() : null);
  const health = rd(join(dir, 'runtime-health.json'));
  if (!health) { console.log('[digest] no runtime-health.json'); return; }
  const incidents = (rd(join(dir, 'incident-state.json')) || {}).incidents || [];
  const actions = rd(join(dir, 'incident-actions.json'));
  const state = rd(join(dir, 'digest-state.json')) || {};
  const now = Date.now();

  const schedule = computeDigestSchedule(now, state);
  const data = renderDigestData({ health, incidents, actions, schedule, now });
  const md = renderDigest(data);

  const enabled = String(process.env.OPS_DIGEST_DELIVERY_ENABLED || 'false') === 'true';
  const dryRun = String(process.env.OPS_DIGEST_DRY_RUN || 'true') !== 'false';
  const delivery = deliverDigest(nullDigestAdapter, data, { enabled, dryRun });

  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'daily-digest.json'), JSON.stringify(data, null, 2));
  writeFileSync(join(dir, 'daily-digest.md'), md);
  // Preview = the EXACT sanitized body that WOULD be delivered when eligible.
  writeFileSync(join(dir, 'daily-digest-preview.md'), `> DELIVERY: ${delivery.mode} · due this window: ${schedule.due} (${schedule.reason}) · would-send subject: "${delivery.subject}"\n> External messages sent: 0\n\n---\n\n${md}`);

  // Dedup state: always record generation; record "delivered window" only when a real send
  // happened (never in V6). This is what makes eligibility fire at most once per UTC day.
  const newState = { schemaVersion: DIGEST_STATE_SCHEMA, lastDigestWindow: schedule.window, lastDigestGeneratedAt: data.generatedAt, digestId: data.digestId, lastDigestDeliveredAt: delivery.delivered ? data.generatedAt : (state.lastDigestDeliveredAt || null), lastDigestDeliveredWindow: delivery.delivered ? schedule.window : (state.lastDigestDeliveredWindow || null) };
  writeFileSync(join(dir, 'digest-state.json'), JSON.stringify(newState, null, 2));
  console.log(`[digest] window=${schedule.window} due=${schedule.due} (${schedule.reason}) delivery=${delivery.mode} sent=0`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
