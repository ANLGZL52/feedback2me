#!/usr/bin/env node
// Observability V6/V7 — daily digest. Rolling-24h operational summary as a markdown +
// JSON artifact, with a transport-independent delivery abstraction. EXTERNAL DELIVERY IS
// LIVE via Slack (V7): armed by OPS_DIGEST_DELIVERY_ENABLED=true + OPS_DIGEST_DRY_RUN=false
// with the OPS_SLACK_WEBHOOK_URL secret. Absent secret => adapter NOT_CONFIGURED (0 sends,
// still green). Deterministic once-per-UTC-day eligibility so repeated 30-min runs never
// duplicate a send. Slack = daily digest ONLY (CRITICAL incidents stay on GitHub Issues).
// No PII / no raw logs / no user content.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { validateIssuePayload } from './incident-actions.mjs';

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
    '', `_Operational metadata only — no raw logs, no user data. Delivered to Slack once per UTC day (V7); CRITICAL incidents stay on GitHub Issues._`];
  return L.join('\n');
}

/** Concise, phone-readable digest body for chat transports (Slack/email). Plain text,
 *  transport-neutral. No raw logs / no PII. Kept short by design (Phase 6). */
export function renderDigestText(d) {
  const t = d.trends || {}, ic = d.incidentCounts || {}, dh = d.domainHealth || {};
  const tr = (k, label) => (t[k] ? `• ${label}: ${t[k]}` : null);
  return [
    `Feedback2Me — Daily Ops Digest`,
    ``,
    `Runtime: ${d.runtimeStatus}`,
    `Observability: ${d.observabilityPlatform}`,
    `Release Gate: ${d.releaseGate}`,
    ``,
    `Incidents`,
    `• Active: ${ic.active} (flapping ${ic.flapping})`,
    `• Opened 24h: ${ic.opened}`,
    `• Resolved 24h: ${ic.resolved}`,
    ``,
    `Services`,
    `• IAP: ${dh.iap}  • OpenAI: ${dh.openai}  • Railway: ${dh.railway}`,
    `• Postgres: ${dh.postgres}  • Collector: ${dh.collector}  • Service: ${dh.service}`,
    ``,
    `Incident Delivery`,
    `• ${d.deliveryHealth?.mode || 'n/a'} / ${d.deliveryHealth?.health || 'n/a'} (failures ${d.deliveryHealth?.failures ?? 0})`,
    ``,
    `Trends`,
    ...([tr('openaiLatencyP95', 'OpenAI latency'), tr('railway5xx', 'Railway 5xx'), tr('iapVerifyFailures', 'IAP verify failures')].filter(Boolean)),
    ``,
    `Deferred`,
    `• Real IAP E2E: ${d.realIapE2E}`,
    ``,
    `Commit: ${d.deploymentContext?.commit || '—'}`,
    `Generated: ${d.generatedAt}`,
  ].join('\n');
}

/**
 * Dedup/eligibility decision (Phase 11). Pure. At most ONE digest per UTC-day window.
 * `configured` = a real transport is available. Never sends when disabled/dry-run/
 * not-configured/not-due/already-delivered-this-window.
 */
export function shouldDeliverDigest(schedule, state = {}, { enabled = false, dryRun = true, configured = false } = {}) {
  if (!enabled) return { send: false, reason: 'disabled' };
  if (dryRun) return { send: false, reason: 'dry_run' };
  if (!configured) return { send: false, reason: 'not_configured' };
  if (!schedule || !schedule.due) return { send: false, reason: (schedule && schedule.reason) || 'not_due' };
  if (state.lastDigestDeliveredWindow === schedule.window) return { send: false, reason: 'already_delivered' };
  return { send: true, reason: 'due' };
}

// ---- transport-independent delivery (Phases 7/9/12/13) ----
// adapter contract: { name, configured:boolean, async send(text, meta) -> {ok, status, latencyMs} }
export async function deliverDigest(adapter, data, { enabled = false, dryRun = true, schedule = null, state = {}, now = null } = {}) {
  const channel = (adapter && adapter.name) || 'none';
  const configured = !!(adapter && adapter.configured);
  const base = { delivered: false, channel, digestId: data.digestId, window: (schedule && schedule.window) || data.digestId, generatedAt: data.generatedAt };
  const mk = (o) => ({ ...base, ...o });
  if (!enabled) return mk({ mode: 'DISABLED', health: 'IDLE', event: 'digest.delivery.skipped', reason: 'disabled' });
  if (dryRun) return mk({ mode: 'DRY_RUN', health: 'IDLE', event: 'digest.delivery.skipped', reason: 'dry_run' });
  if (!configured) return mk({ mode: 'LIVE', health: 'NOT_CONFIGURED', event: 'digest.delivery.not_configured', reason: 'not_configured' });
  const decision = shouldDeliverDigest(schedule, state, { enabled, dryRun, configured });
  if (!decision.send) return mk({ mode: 'LIVE', health: 'IDLE', event: 'digest.delivery.skipped', reason: decision.reason });
  // Payload safety (Phase 7): nothing unsafe ever reaches the transport.
  const text = renderDigestText(data);
  const safe = validateIssuePayload('digest', text);
  if (!safe.safe) return mk({ mode: 'LIVE', health: 'DEGRADED', event: 'digest.delivery.payload_rejected', reason: 'unsafe_payload', code: 'DIGEST_DELIVERY_PAYLOAD_REJECTED' });
  const deliveredAt = now ? new Date(now).toISOString() : new Date().toISOString();
  try {
    const r = (await adapter.send(text, { digestId: data.digestId, generatedAt: data.generatedAt })) || {};
    if (r.ok) return mk({ delivered: true, mode: 'LIVE', health: 'HEALTHY', event: 'digest.delivery.sent', reason: 'sent', statusCode: r.status ?? null, latencyMs: r.latencyMs ?? null, deliveredAt });
    const health = (r.status >= 500 || r.status === 429) ? 'UNAVAILABLE' : 'DEGRADED';
    return mk({ mode: 'LIVE', health, event: 'digest.delivery.failed', reason: 'transport_failed', statusCode: r.status ?? null, latencyMs: r.latencyMs ?? null, code: 'DIGEST_DELIVERY_FAILED' });
  } catch (e) {
    return mk({ mode: 'LIVE', health: 'UNAVAILABLE', event: 'digest.delivery.failed', reason: 'exception', code: 'DIGEST_DELIVERY_FAILED' });
  }
}
// Null adapter — never configured; real Slack/email/Discord adapters plug in at this boundary.
export const nullDigestAdapter = { name: 'null', configured: false, send: async () => ({ ok: false }) };

async function main() {
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
  // Slack is the first external transport. The webhook comes ONLY from a GitHub Actions
  // secret (SLACK_WEBHOOK_URL) injected into this step — never from source/YAML literals.
  // Absent secret => configured:false => NOT_CONFIGURED (0 messages, workflow stays green).
  const { slackDigestAdapter } = await import('./slack-digest-adapter.mjs');
  const adapter = slackDigestAdapter(process.env.SLACK_WEBHOOK_URL || '');
  const delivery = await deliverDigest(adapter, data, { enabled, dryRun, schedule, state, now });

  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'daily-digest.json'), JSON.stringify(data, null, 2));
  writeFileSync(join(dir, 'daily-digest.md'), md);
  // Preview = the EXACT sanitized text that WOULD be delivered when eligible. No webhook.
  writeFileSync(join(dir, 'daily-digest-preview.md'), `> DELIVERY: channel=${delivery.channel} mode=${delivery.mode} health=${delivery.health} · due=${schedule.due} (${schedule.reason}) · sent=${delivery.delivered ? 1 : 0}\n\n---\n\n${renderDigestText(data)}`);

  // Delivery event (Phase 13) — safe, low-cardinality. NEVER the webhook or message body.
  const event = { event: delivery.event, channel: delivery.channel, digestId: delivery.digestId, window: delivery.window, result: delivery.reason, statusCode: delivery.statusCode ?? null, latencyMs: delivery.latencyMs ?? null, timestamp: new Date(now).toISOString() };
  writeFileSync(join(dir, 'digest-delivery.json'), JSON.stringify({ generatedAt: new Date(now).toISOString(), mode: delivery.mode, channel: delivery.channel, health: delivery.health, delivered: delivery.delivered, code: delivery.code || null, event }, null, 2));

  // Dedup state (Phase 11): record the delivered window ONLY on a real successful send —
  // that is what makes a second run in the same window skip (already_delivered).
  const newState = { schemaVersion: DIGEST_STATE_SCHEMA, lastDigestWindow: schedule.window, lastDigestGeneratedAt: data.generatedAt, digestId: data.digestId, lastDigestDeliveredAt: delivery.delivered ? (delivery.deliveredAt || new Date(now).toISOString()) : (state.lastDigestDeliveredAt || null), lastDigestDeliveredWindow: delivery.delivered ? schedule.window : (state.lastDigestDeliveredWindow || null), deliveryChannel: delivery.delivered ? delivery.channel : (state.deliveryChannel || null) };
  writeFileSync(join(dir, 'digest-state.json'), JSON.stringify(newState, null, 2));
  console.log(`[digest] window=${schedule.window} due=${schedule.due} (${schedule.reason}) channel=${delivery.channel} mode=${delivery.mode} health=${delivery.health} sent=${delivery.delivered ? 1 : 0}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main().catch((e) => console.log('[digest] fatal (contained): ' + e.message));
