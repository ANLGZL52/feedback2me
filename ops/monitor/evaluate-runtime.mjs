#!/usr/bin/env node
// Observability V3 — runtime health EVALUATOR. Consumes the normalized, PII-safe
// runtime events (ops-status/runtime-events/*.jsonl) + the central SLO contract
// (ops/observability-slo.json) and produces a machine artifact
// (ops-status/runtime-health.json) + a human report. Deterministic + pure at the
// core (evaluate()) so it is fully unit-testable with fixtures. NO network in the
// pure core; NO secrets/PII ever emitted.
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { computeIapMetrics, detectMoneySafetyViolations } from './iap-invariants.mjs';

const HEALTHY = 'HEALTHY', DEGRADED = 'DEGRADED', UNHEALTHY = 'UNHEALTHY', UNKNOWN = 'UNKNOWN', IDLE = 'IDLE';
const worst = (a, b) => {
  const rank = { [UNKNOWN]: 0, [IDLE]: 1, [HEALTHY]: 2, [DEGRADED]: 3, [UNHEALTHY]: 4 };
  return rank[b] > rank[a] ? b : a;
};

function alert(domain, code, severity, message, evidence, releaseBlocking = false) {
  return { domain, code, severity, message, evidence: evidence || null, releaseBlocking };
}

// ---------- domain evaluators (pure) ----------

function evalIap(events, slo, observabilityOk, iapVerifyReachable) {
  const m = computeIapMetrics(events);
  const violations = detectMoneySafetyViolations(events);
  const alerts = [];
  // Money-safety invariants: CRITICAL + releaseBlocking, ALWAYS (no min sample).
  for (const v of violations) alerts.push(alert('IAP', v.code, 'CRITICAL', v.message, v.evidence, true));
  if (violations.length) alerts.push(alert('IAP', 'IAP_MONEY_SAFETY_BREACH', 'CRITICAL', `${violations.length} money-safety invariant breach(es)`, { codes: violations.map((v) => v.code) }, true));

  // iapVerify availability (from a smoke probe when provided; null = not probed).
  if (iapVerifyReachable === false) alerts.push(alert('IAP', 'IAP_VERIFY_DOWN', 'CRITICAL', 'iapVerify callable is unreachable', null, true));

  const attempts = m.counts.verifyAttempts;
  const failures = m.counts.rejected + m.counts.transientFailure + m.counts.error;
  const s = slo.iap;
  // Failure-rate: require BOTH min sample AND an absolute-failure floor (low-traffic-safe).
  if (attempts >= s.minSampleForRate && failures >= s.verifyFailureRate.minAbsoluteFailures) {
    const fr = failures / attempts;
    if (fr >= s.verifyFailureRate.critical) alerts.push(alert('IAP', 'IAP_VERIFY_FAILURE_ELEVATED', 'CRITICAL', `verify failure rate ${(fr * 100).toFixed(0)}% (${failures}/${attempts})`, { failureRate: fr }));
    else if (fr >= s.verifyFailureRate.warn) alerts.push(alert('IAP', 'IAP_VERIFY_FAILURE_ELEVATED', 'WARNING', `verify failure rate ${(fr * 100).toFixed(0)}% (${failures}/${attempts})`, { failureRate: fr }));
  }
  if (m.counts.transientFailure >= s.transientFailure.criticalCount) alerts.push(alert('IAP', 'IAP_TRANSIENT_FAILURE_SUSTAINED', 'CRITICAL', `${m.counts.transientFailure} Apple transient failures`, null));
  else if (m.counts.transientFailure >= s.transientFailure.warnCount) alerts.push(alert('IAP', 'IAP_TRANSIENT_FAILURE_SUSTAINED', 'WARNING', `${m.counts.transientFailure} Apple transient failures`, null));
  if (m.counts.rejected >= s.rejectedSpike.criticalCount) alerts.push(alert('IAP', 'IAP_REJECTED_SPIKE', 'CRITICAL', `${m.counts.rejected} Apple rejections`, null));
  else if (m.counts.rejected >= s.rejectedSpike.warnCount) alerts.push(alert('IAP', 'IAP_REJECTED_SPIKE', 'WARNING', `${m.counts.rejected} Apple rejections`, null));
  if (m.latencyMs.p95 != null) {
    if (m.latencyMs.p95 >= s.latencyMsP95.critical) alerts.push(alert('IAP', 'IAP_LATENCY_DEGRADED', 'CRITICAL', `verify p95 latency ${m.latencyMs.p95}ms`, { p95: m.latencyMs.p95 }));
    else if (m.latencyMs.p95 >= s.latencyMsP95.warn) alerts.push(alert('IAP', 'IAP_LATENCY_DEGRADED', 'WARNING', `verify p95 latency ${m.latencyMs.p95}ms`, { p95: m.latencyMs.p95 }));
  }

  let status = HEALTHY;
  if (!observabilityOk) status = UNKNOWN;
  else if (alerts.some((a) => a.severity === 'CRITICAL')) status = UNHEALTHY;
  else if (alerts.some((a) => a.severity === 'WARNING')) status = DEGRADED;
  else if (m.sampleSize === 0 && iapVerifyReachable !== false) status = IDLE; // NO_TRAFFIC (not a failure)
  return { status, metrics: m, alerts };
}

function evalOpenAi(events, slo, observabilityOk) {
  const oai = (events || []).filter((e) => e && typeof e.eventType === 'string' && e.eventType.startsWith('openai.'));
  const c = (t) => oai.filter((e) => e.eventType === t).length;
  const completed = c('openai.request.completed');
  const failed = c('openai.request.failed') + c('openai.timeout') + c('openai.rate_limited') + c('openai.fallback.required');
  const total = completed + c('openai.request.failed') + c('openai.timeout');
  const lat = oai.map((e) => (e.openai && typeof e.openai.latencyMs === 'number' ? e.openai.latencyMs : null)).filter((x) => x != null).sort((a, b) => a - b);
  const p95 = lat.length ? lat[Math.min(lat.length - 1, Math.floor(0.95 * lat.length))] : null;
  const toks = oai.map((e) => (e.openai && typeof e.openai.totalTokens === 'number' ? e.openai.totalTokens : null)).filter((x) => x != null);
  const avgTok = toks.length ? Math.round(toks.reduce((a, b) => a + b, 0) / toks.length) : null;
  const alerts = [];
  const s = slo.openai;
  if (total >= s.minSampleForRate && failed >= s.failureRate.minAbsoluteFailures) {
    const fr = failed / total;
    if (fr >= s.failureRate.critical) alerts.push(alert('OPENAI', 'OPENAI_DEGRADED', 'CRITICAL', `OpenAI failure rate ${(fr * 100).toFixed(0)}%`, { failureRate: fr }));
    else if (fr >= s.failureRate.warn) alerts.push(alert('OPENAI', 'OPENAI_DEGRADED', 'WARNING', `OpenAI failure rate ${(fr * 100).toFixed(0)}%`, { failureRate: fr }));
  }
  if (p95 != null && p95 >= s.latencyMsP95.critical) alerts.push(alert('OPENAI', 'OPENAI_LATENCY_DEGRADED', 'CRITICAL', `OpenAI p95 ${p95}ms`, { p95 }));
  else if (p95 != null && p95 >= s.latencyMsP95.warn) alerts.push(alert('OPENAI', 'OPENAI_LATENCY_DEGRADED', 'WARNING', `OpenAI p95 ${p95}ms`, { p95 }));
  if (avgTok != null && avgTok >= s.tokenSpike.warnTotalTokensPerRequest) alerts.push(alert('OPENAI', 'OPENAI_TOKEN_SPIKE', 'WARNING', `avg ${avgTok} total tokens/request`, { avgTotalTokens: avgTok }));
  let status = HEALTHY;
  if (!observabilityOk) status = UNKNOWN;
  else if (alerts.some((a) => a.severity === 'CRITICAL')) status = UNHEALTHY;
  else if (alerts.some((a) => a.severity === 'WARNING')) status = DEGRADED;
  else if (total === 0) status = IDLE;
  return { status, metrics: { requests: total, completed, failed, latencyP95Ms: p95, avgTotalTokens: avgTok }, alerts };
}

function evalRailway(events, slo, observabilityOk, railwayReachable) {
  const http = (events || []).filter((e) => e && e.source === 'railway-http');
  const cls = (k) => http.filter((e) => e.statusClass === k).length;
  const c2 = cls('2xx'), c3 = cls('3xx'), c4 = cls('4xx'), c5 = cls('5xx');
  const total = http.length;
  const alerts = [];
  const s = slo.railway;
  if (railwayReachable === false) alerts.push(alert('RAILWAY', 'RAILWAY_UNREACHABLE', 'WARNING', 'collector could not reach Railway (NOT a confirmed backend outage)', null));
  if (c5 >= s.min5xxAbsolute && total >= s.http5xxRate.minSampleForRate) {
    const r5 = c5 / total;
    if (r5 >= s.http5xxRate.critical) alerts.push(alert('RAILWAY', 'RAILWAY_5XX_ELEVATED', 'CRITICAL', `5xx rate ${(r5 * 100).toFixed(0)}% (${c5}/${total})`, { rate: r5 }));
    else if (r5 >= s.http5xxRate.warn) alerts.push(alert('RAILWAY', 'RAILWAY_5XX_ELEVATED', 'WARNING', `5xx rate ${(r5 * 100).toFixed(0)}% (${c5}/${total})`, { rate: r5 }));
  }
  let status = HEALTHY;
  if (!observabilityOk) status = UNKNOWN;
  else if (alerts.some((a) => a.severity === 'CRITICAL')) status = UNHEALTHY;
  else if (alerts.some((a) => a.severity === 'WARNING')) status = DEGRADED;
  else if (total === 0) status = IDLE; // NO_TRAFFIC — not a failure
  return { status, metrics: { requests: total, '2xx': c2, '3xx': c3, '4xx': c4, '5xx': c5 }, alerts };
}

function evalPostgres(pg, slo) {
  // pg: { status: 'HEALTHY'|'DEGRADED'|'DOWN'|'UNKNOWN', consecutiveFailures?: number } | null
  const alerts = [];
  if (!pg || pg.status === 'UNKNOWN' || pg.status == null) return { status: UNKNOWN, metrics: { probe: pg?.status || 'NOT_CONFIGURED' }, alerts };
  const s = slo.postgres;
  const consec = pg.consecutiveFailures || 0;
  if (pg.status === 'DOWN' || pg.status === 'DEGRADED') {
    if (consec >= s.consecutiveFailures.critical) alerts.push(alert('POSTGRES', 'POSTGRES_CRITICAL', 'CRITICAL', `Postgres unhealthy for ${consec} consecutive probes`, { consecutiveFailures: consec }, false));
    else alerts.push(alert('POSTGRES', 'POSTGRES_WARNING', 'WARNING', `Postgres probe ${pg.status}`, { consecutiveFailures: consec }));
  }
  let status = HEALTHY;
  if (alerts.some((a) => a.severity === 'CRITICAL')) status = UNHEALTHY;
  else if (alerts.some((a) => a.severity === 'WARNING')) status = DEGRADED;
  return { status, metrics: { probe: pg.status, consecutiveFailures: consec }, alerts };
}

function evalCollector(collector, slo, now) {
  // collector: { lastEventAt: ISO|null, ranOk: bool, providersAttempted, providersSucceeded }
  const alerts = [];
  const staleMs = slo.collector.staleMinutes * 60000;
  const last = collector && collector.lastEventAt ? Date.parse(collector.lastEventAt) : null;
  const ageMin = last != null ? Math.round((now - last) / 60000) : null;
  let status = HEALTHY;
  if (!collector || collector.ranOk === false) { status = UNKNOWN; alerts.push(alert('COLLECTOR', 'COLLECTOR_RUN_FAILED', 'WARNING', 'collector run did not complete successfully', null)); }
  else if (last == null) { status = UNKNOWN; }
  else if (now - last > staleMs) { status = UNHEALTHY; alerts.push(alert('COLLECTOR', 'COLLECTOR_STALE', 'CRITICAL', `no fresh collection for ${ageMin} min (> ${slo.collector.staleMinutes})`, { ageMinutes: ageMin }, true)); }
  return { status, metrics: { lastEventAt: collector?.lastEventAt || null, ageMinutes: ageMin, providersSucceeded: collector?.providersSucceeded ?? null, providersAttempted: collector?.providersAttempted ?? null }, alerts };
}

/**
 * PURE evaluator. Deterministic given inputs. `now` is ms epoch (injected for tests).
 * `prev` is the previous artifact (for NEW/ONGOING/RESOLVED). No file/network here.
 */
export function evaluate({ events = [], slo, now, prev = null, signals = {}, deployment = null, iapE2eEvidence = null, security = null }) {
  const observabilityOk = signals.observabilityOk !== false; // false only when the collector genuinely failed
  const iap = evalIap(events, slo, observabilityOk, signals.iapVerifyReachable ?? null);
  const openai = evalOpenAi(events, slo, observabilityOk);
  const railway = evalRailway(events, slo, observabilityOk, signals.railwayReachable ?? null);
  const postgres = evalPostgres(signals.postgres ?? null, slo);
  const collector = evalCollector(signals.collector ?? null, slo, now);

  // Security domain: an explicit leak signal (from the collector's own PII scan).
  const securityAlerts = [];
  if (security && security.leak === true) securityAlerts.push(alert('SECURITY', 'SECRET_OR_PII_LEAK', 'CRITICAL', 'a secret/PII pattern was detected in collected events', { count: security.count ?? null }, true));

  const domains = { IAP: iap, OPENAI: openai, RAILWAY: railway, POSTGRES: postgres, COLLECTOR: collector, SECURITY: { status: securityAlerts.length ? UNHEALTHY : HEALTHY, metrics: {}, alerts: securityAlerts } };

  // Flatten alerts.
  let alerts = [];
  for (const d of Object.values(domains)) alerts = alerts.concat(d.alerts);

  // Missing real IAP E2E evidence is release-blocking (honest: ASSUMED != VERIFIED).
  const e2eVerified = !!(iapE2eEvidence && iapE2eEvidence.verified === true);
  if (!e2eVerified) alerts.push(alert('RELEASE', 'MISSING_IAP_E2E_EVIDENCE', 'WARNING', 'no verified real TestFlight sandbox purchase evidence yet (ops-status/iap-e2e-evidence.json verified=true required)', { present: !!iapE2eEvidence }, true));

  // Alert identity + NEW/ONGOING/RESOLVED vs prev.
  const idOf = (a) => `${a.domain}:${a.code}`;
  const prevAlerts = (prev && prev.alerts) || [];
  const prevIds = new Set(prevAlerts.filter((a) => a.state !== 'RESOLVED').map(idOf));
  const curIds = new Set(alerts.map(idOf));
  const nowIso = new Date(now).toISOString();
  const tracked = alerts.map((a) => {
    const wasOpen = prevIds.has(idOf(a));
    const prevA = prevAlerts.find((p) => idOf(p) === idOf(a));
    return { ...a, state: wasOpen ? 'ONGOING' : 'NEW', firstSeen: (prevA && prevA.firstSeen) || nowIso, lastSeen: nowIso };
  });
  // Resolved: previously open, not present now.
  const resolved = prevAlerts
    .filter((a) => a.state !== 'RESOLVED' && !curIds.has(idOf(a)))
    .map((a) => ({ ...a, state: 'RESOLVED', lastSeen: nowIso }));

  // Overall runtime health (UNKNOWN-aware: collector UNKNOWN doesn't mask a real UNHEALTHY).
  let overallStatus = HEALTHY;
  for (const d of Object.values(domains)) if (d.status !== IDLE) overallStatus = worst(overallStatus, d.status);
  if (overallStatus === HEALTHY && Object.values(domains).every((d) => d.status === IDLE || d.status === UNKNOWN)) {
    overallStatus = Object.values(domains).some((d) => d.status === IDLE) ? IDLE : UNKNOWN;
  }

  // Release gate. An alert blocks if it carries releaseBlocking OR its code is in
  // the SLO blockOn list (e.g. POSTGRES_CRITICAL blocks without a per-alert flag).
  const blocking = tracked.filter((a) => a.releaseBlocking === true || slo.releaseGate.blockOn.includes(a.code));
  const warns = tracked.filter((a) => !blocking.includes(a) && (a.severity === 'WARNING' || a.severity === 'CRITICAL'));
  const releaseGate = { status: blocking.length ? 'BLOCK' : warns.length ? 'WARN' : 'PASS', blocking: blocking.map((a) => a.code), warnings: warns.map((a) => a.code) };

  return {
    generatedAt: nowIso,
    window: { lookbackHours: slo.window.lookbackHours, events: events.length },
    overallStatus,
    releaseGate,
    domains: Object.fromEntries(Object.entries(domains).map(([k, v]) => [k, { status: v.status, metrics: v.metrics }])),
    alerts: tracked,
    resolvedAlerts: resolved,
    deploymentContext: deployment || null,
    validationEvidence: { iapRealE2E: e2eVerified ? 'VERIFIED' : 'ASSUMED_FOR_NEXT_PHASE', source: iapE2eEvidence?.source || null },
  };
}

// ---------- human report ----------
export function renderReport(a) {
  const L = [];
  L.push(`# Feedback2Me Runtime Health`);
  L.push(``);
  L.push(`Generated: ${a.generatedAt}  ·  window: ${a.window.lookbackHours}h  ·  events: ${a.window.events}`);
  L.push(`Overall: **${a.overallStatus}**   ·   Release Gate: **${a.releaseGate.status}**`);
  const d = a.domains;
  const line = (name, dom, extra) => L.push(`- **${name}**: ${dom.status}${extra ? ' — ' + extra : ''}`);
  L.push(``); L.push(`## Domains`);
  line('IAP', d.IAP, `verify ${d.IAP.metrics.counts?.verifyAttempts ?? 0} (ok ${d.IAP.metrics.counts?.success ?? 0}/fail ${(d.IAP.metrics.counts?.rejected ?? 0) + (d.IAP.metrics.counts?.transientFailure ?? 0) + (d.IAP.metrics.counts?.error ?? 0)}), grants ${d.IAP.metrics.counts?.creditGranted ?? 0}, replays ${d.IAP.metrics.counts?.creditReplay ?? 0}, p95 ${d.IAP.metrics.latencyMs?.p95 ?? '—'}ms`);
  line('OpenAI', d.OPENAI, `req ${d.OPENAI.metrics.requests}, fail ${d.OPENAI.metrics.failed}, p95 ${d.OPENAI.metrics.latencyP95Ms ?? '—'}ms`);
  line('Railway', d.RAILWAY, `req ${d.RAILWAY.metrics.requests} (5xx ${d.RAILWAY.metrics['5xx']})`);
  line('Postgres', d.POSTGRES, `${d.POSTGRES.metrics.probe}`);
  line('Collector', d.COLLECTOR, `last ${d.COLLECTOR.metrics.lastEventAt || '—'} (${d.COLLECTOR.metrics.ageMinutes ?? '—'} min)`);
  L.push(``); L.push(`## Active Alerts`);
  if (!a.alerts.length) L.push(`- none`);
  for (const al of a.alerts) L.push(`- [${al.severity}] ${al.domain}/${al.code} — ${al.message}${al.releaseBlocking ? ' *(release-blocking)*' : ''} (${al.state})`);
  if (a.resolvedAlerts.length) { L.push(``); L.push(`## Resolved`); for (const al of a.resolvedAlerts) L.push(`- ${al.domain}/${al.code}`); }
  L.push(``); L.push(`## Release Evidence`);
  L.push(`- IAP real E2E: **${a.validationEvidence.iapRealE2E}**`);
  if (a.deploymentContext) L.push(`- deploy: commit ${a.deploymentContext.commit || '—'} · build ${a.deploymentContext.build || '—'} · fn ${a.deploymentContext.functionRevision || '—'}`);
  return L.join('\n');
}

// ---------- file-driven runner ----------
function readEventsWindow(dir, lookbackHours, now) {
  if (!existsSync(dir)) return [];
  const cutoff = now - lookbackHours * 3600000;
  const out = [];
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.jsonl'))) {
    for (const line of readFileSync(join(dir, f), 'utf8').split('\n')) {
      if (!line.trim()) continue;
      try { const e = JSON.parse(line); const t = e.timestamp ? Date.parse(e.timestamp) : null; if (t == null || t >= cutoff) out.push(e); } catch {}
    }
  }
  return out;
}

function main() {
  const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const slo = JSON.parse(readFileSync(join(REPO, 'ops', 'observability-slo.json'), 'utf8'));
  const now = Date.now();
  const evDir = join(REPO, 'ops-status', 'runtime-events');
  const events = readEventsWindow(evDir, slo.window.lookbackHours, now);

  // Collector freshness = WHEN THE COLLECTOR LAST WROTE (newest runtime-events file
  // mtime), NOT the newest event timestamp — a successful collection with only
  // pre-window or timestamp-less events still proves the collector ran (fresh).
  // A missing/empty dir means no collection happened -> UNKNOWN (NO_OBSERVABILITY).
  let lastCollectionMs = null;
  if (existsSync(evDir)) {
    for (const f of readdirSync(evDir).filter((x) => x.endsWith('.jsonl'))) {
      try { const m = statSync(join(evDir, f)).mtimeMs; if (lastCollectionMs == null || m > lastCollectionMs) lastCollectionMs = m; } catch {}
    }
  }
  const collector = { lastEventAt: lastCollectionMs ? new Date(lastCollectionMs).toISOString() : null, ranOk: existsSync(evDir) && lastCollectionMs != null, providersAttempted: 3, providersSucceeded: null };

  // deployment correlation: derive from the CURRENT source (git HEAD + pubspec),
  // not a possibly-stale control-plane snapshot. functionRevision when discoverable.
  let commit = null, build = null;
  try { commit = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: REPO }).toString().trim(); } catch {}
  try { build = (readFileSync(join(REPO, 'pubspec.yaml'), 'utf8').match(/^version:\s*[\d.]+\+(\d+)/m) || [])[1] || null; } catch {}
  const deployment = { commit, build, functionRevision: process.env.IAPVERIFY_REVISION || null };

  // postgres from the control-plane snapshot when present (it already probes it).
  let signals = { collector, observabilityOk: existsSync(evDir) };
  const latestP = join(REPO, 'ops-status', 'latest.json');
  if (existsSync(latestP)) {
    try {
      const snap = JSON.parse(readFileSync(latestP, 'utf8'));
      const pg = (snap.components && (snap.components['node-postgres'] || snap.components['postgres'])) || null;
      if (pg) signals.postgres = { status: pg.status, consecutiveFailures: pg.consecutiveFailures || 0 };
    } catch {}
  }
  // real IAP E2E evidence (only counts when verified=true).
  let iapE2eEvidence = null;
  const e2eP = join(REPO, 'ops-status', 'iap-e2e-evidence.json');
  if (existsSync(e2eP)) { try { iapE2eEvidence = JSON.parse(readFileSync(e2eP, 'utf8')); } catch {} }

  // prev artifact for NEW/ONGOING/RESOLVED.
  let prev = null;
  const outP = join(REPO, 'ops-status', 'runtime-health.json');
  if (existsSync(outP)) { try { prev = JSON.parse(readFileSync(outP, 'utf8')); } catch {} }

  const artifact = evaluate({ events, slo, now, prev, signals, deployment, iapE2eEvidence });
  if (!existsSync(join(REPO, 'ops-status'))) mkdirSync(join(REPO, 'ops-status'), { recursive: true });
  writeFileSync(outP, JSON.stringify(artifact, null, 2));
  writeFileSync(join(REPO, 'ops-status', 'runtime-health.md'), renderReport(artifact) + '\n');
  console.log(renderReport(artifact));
  console.log(`\n[evaluate] wrote ${outP} + runtime-health.md`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
