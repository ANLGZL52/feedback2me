// Observability V3 evaluator tests — deterministic fixtures (no network/providers).
// Run: node --test ops/monitor/evaluate-runtime.test.mjs
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { evaluate, renderReport } from './evaluate-runtime.mjs';
import { computeIapMetrics, detectMoneySafetyViolations } from './iap-invariants.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SLO = JSON.parse(readFileSync(join(REPO, 'ops', 'observability-slo.json'), 'utf8'));
const NOW = Date.parse('2026-08-19T12:00:00Z');
const TS = new Date(NOW - 60000).toISOString(); // 1 min ago (fresh)

// --- event builders ---
const iapEv = (eventType, iap = {}, ts = TS) => ({
  timestamp: ts, source: 'gcp-functions', service: 'iapVerify', eventType,
  severity: 'INFO', errorCode: null, provider: iap.provider || 'apple',
  iap: { platform: 'ios', productId: 'premium_link_single_v2', resultClass: 'ok', latencyMs: 300, creditDelta: null, replay: null, clientRequestId: 'op-x', txCorrelation: null, ...iap },
});
// one healthy purchase op (started -> success -> granted), all sharing clientRequestId + txCorrelation
const purchaseOp = (id, tx) => [
  iapEv('iap.verify.started', { clientRequestId: id }),
  iapEv('iap.verify.apple.success', { clientRequestId: id, resultClass: 'ok', latencyMs: 320 }),
  iapEv('iap.credit.granted', { clientRequestId: id, creditDelta: 1, replay: false, txCorrelation: tx, latencyMs: 380 }),
];
const oaiEv = (eventType, openai = {}) => ({ timestamp: TS, source: 'gcp-functions', service: 'aiSummary', eventType, provider: 'openai', openai: { statusClass: '2xx', latencyMs: 2000, totalTokens: 800, ...openai } });
const httpEv = (statusClass) => ({ timestamp: TS, source: 'railway-http', method: 'POST', routeId: 'POST /feedbacks', statusClass, httpStatus: statusClass === '5xx' ? 500 : 200, latencyMs: 120 });

const baseSignals = () => ({ collector: { lastEventAt: TS, ranOk: true, providersAttempted: 3, providersSucceeded: 3 }, observabilityOk: true, iapVerifyReachable: true, postgres: { status: 'HEALTHY', consecutiveFailures: 0 } });
const run = (events, over = {}) => evaluate({ events, slo: SLO, now: NOW, prev: null, signals: { ...baseSignals(), ...(over.signals || {}) }, iapE2eEvidence: over.iapE2eEvidence, ...over.extra });

describe('IAP metrics + money-safety invariants (pure)', () => {
  test('healthy purchases -> no violations, correct counts', () => {
    const evs = [...purchaseOp('a', 't:aaa'), ...purchaseOp('b', 't:bbb')];
    assert.equal(detectMoneySafetyViolations(evs).length, 0);
    const m = computeIapMetrics(evs);
    assert.equal(m.counts.success, 2);
    assert.equal(m.counts.creditGranted, 2);
    assert.equal(m.rates.verifySuccess, 1);
  });
  test('A: verification success but NO credit -> IAP_SUCCESS_WITHOUT_CREDIT', () => {
    const evs = [iapEv('iap.verify.started', { clientRequestId: 'z' }), iapEv('iap.verify.apple.success', { clientRequestId: 'z' })];
    assert.ok(detectMoneySafetyViolations(evs).some((v) => v.code === 'IAP_SUCCESS_WITHOUT_CREDIT'));
  });
  test('B: granted with creditDelta != 1 -> IAP_GRANT_DELTA_NOT_ONE', () => {
    const evs = [iapEv('iap.credit.granted', { clientRequestId: 'z', creditDelta: 2, txCorrelation: 't:z' })];
    assert.ok(detectMoneySafetyViolations(evs).some((v) => v.code === 'IAP_GRANT_DELTA_NOT_ONE'));
  });
  test('C: replay with creditDelta != 0 -> IAP_REPLAY_DELTA_NOT_ZERO', () => {
    const evs = [iapEv('iap.credit.replay', { clientRequestId: 'z', creditDelta: 1 })];
    assert.ok(detectMoneySafetyViolations(evs).some((v) => v.code === 'IAP_REPLAY_DELTA_NOT_ZERO'));
  });
  test('D: unknown product credited -> IAP_CREDIT_UNKNOWN_PRODUCT', () => {
    const evs = [iapEv('iap.credit.granted', { clientRequestId: 'z', creditDelta: 1, productId: 'hacker_product', txCorrelation: 't:z' })];
    assert.ok(detectMoneySafetyViolations(evs).some((v) => v.code === 'IAP_CREDIT_UNKNOWN_PRODUCT'));
  });
  test('E: credit granted after a verification failure -> IAP_CREDIT_AFTER_FAILURE', () => {
    const evs = [iapEv('iap.verify.apple.rejected', { clientRequestId: 'z' }), iapEv('iap.credit.granted', { clientRequestId: 'z', creditDelta: 1, txCorrelation: 't:z' })];
    assert.ok(detectMoneySafetyViolations(evs).some((v) => v.code === 'IAP_CREDIT_AFTER_FAILURE'));
  });
  test('F: same store correlation granted twice -> IAP_DUPLICATE_GRANT', () => {
    const evs = [iapEv('iap.credit.granted', { clientRequestId: 'a', creditDelta: 1, txCorrelation: 't:dup' }), iapEv('iap.credit.granted', { clientRequestId: 'b', creditDelta: 1, txCorrelation: 't:dup' })];
    assert.ok(detectMoneySafetyViolations(evs).some((v) => v.code === 'IAP_DUPLICATE_GRANT'));
  });
});

describe('evaluate() — health + alerts + release gate', () => {
  const verified = { iapE2eEvidence: { verified: true, source: 'sandbox' } };

  test('healthy + verified E2E -> HEALTHY, gate PASS', () => {
    const a = run([...purchaseOp('a', 't:a'), oaiEv('openai.request.completed'), httpEv('2xx')], verified);
    assert.equal(a.domains.IAP.status, 'HEALTHY');
    assert.equal(a.releaseGate.status, 'PASS');
    assert.equal(a.overallStatus, 'HEALTHY');
    assert.equal(a.validationEvidence.iapRealE2E, 'VERIFIED');
  });

  test('money-safety breach -> IAP UNHEALTHY + CRITICAL + gate BLOCK', () => {
    const evs = [iapEv('iap.credit.granted', { clientRequestId: 'z', creditDelta: 5, txCorrelation: 't:z' })];
    const a = run(evs, verified);
    assert.equal(a.domains.IAP.status, 'UNHEALTHY');
    assert.ok(a.alerts.some((x) => x.code === 'IAP_MONEY_SAFETY_BREACH' && x.severity === 'CRITICAL' && x.releaseBlocking));
    assert.equal(a.releaseGate.status, 'BLOCK');
  });

  test('iapVerify unreachable -> IAP_VERIFY_DOWN CRITICAL + BLOCK', () => {
    const a = run([], { ...verified, signals: { iapVerifyReachable: false } });
    assert.ok(a.alerts.some((x) => x.code === 'IAP_VERIFY_DOWN' && x.releaseBlocking));
    assert.equal(a.releaseGate.status, 'BLOCK');
  });

  test('missing real E2E evidence -> gate BLOCK (honest), even when healthy', () => {
    const a = run([...purchaseOp('a', 't:a')]); // no iapE2eEvidence
    assert.equal(a.validationEvidence.iapRealE2E, 'ASSUMED_FOR_NEXT_PHASE');
    assert.ok(a.releaseGate.blocking.includes('MISSING_IAP_E2E_EVIDENCE'));
    assert.equal(a.releaseGate.status, 'BLOCK');
  });

  test('OpenAI degraded (>=50% failures, min sample) -> OPENAI UNHEALTHY WARN/CRIT', () => {
    const evs = [oaiEv('openai.request.completed'), oaiEv('openai.request.completed'), oaiEv('openai.request.failed'), oaiEv('openai.request.failed'), oaiEv('openai.timeout')];
    const a = run(evs, verified);
    assert.ok(['DEGRADED', 'UNHEALTHY'].includes(a.domains.OPENAI.status));
    assert.ok(a.alerts.some((x) => x.domain === 'OPENAI' && x.code === 'OPENAI_DEGRADED'));
  });

  test('Railway 5xx outage -> RAILWAY alert', () => {
    const evs = [];
    for (let i = 0; i < 8; i++) evs.push(httpEv('5xx'));
    for (let i = 0; i < 2; i++) evs.push(httpEv('2xx'));
    const a = run(evs, verified);
    assert.ok(a.alerts.some((x) => x.domain === 'RAILWAY' && x.code === 'RAILWAY_5XX_ELEVATED'));
  });

  test('Postgres 3 consecutive failures -> POSTGRES_CRITICAL + BLOCK', () => {
    const a = run([...purchaseOp('a', 't:a')], { ...verified, signals: { postgres: { status: 'DOWN', consecutiveFailures: 3 } } });
    assert.equal(a.domains.POSTGRES.status, 'UNHEALTHY');
    assert.ok(a.alerts.some((x) => x.code === 'POSTGRES_CRITICAL'));
    assert.equal(a.releaseGate.status, 'BLOCK');
  });

  test('collector stale -> COLLECTOR_STALE CRITICAL + BLOCK', () => {
    const stale = new Date(NOW - 200 * 60000).toISOString();
    const a = run([...purchaseOp('a', 't:a')], { ...verified, signals: { collector: { lastEventAt: stale, ranOk: true }, observabilityOk: true } });
    assert.ok(a.alerts.some((x) => x.code === 'COLLECTOR_STALE' && x.releaseBlocking));
    assert.equal(a.releaseGate.status, 'BLOCK');
  });

  test('no traffic (fresh collector) -> IDLE not failure, gate not blocked by traffic', () => {
    const a = run([], verified);
    assert.equal(a.domains.IAP.status, 'IDLE');
    assert.equal(a.domains.RAILWAY.status, 'IDLE');
    // gate PASS (no blocking alert; E2E verified in this fixture)
    assert.equal(a.releaseGate.status, 'PASS');
  });

  test('NO_OBSERVABILITY (collector failed) -> UNKNOWN, distinct from IDLE', () => {
    const a = run([], { ...verified, signals: { collector: { ranOk: false }, observabilityOk: false } });
    assert.equal(a.domains.IAP.status, 'UNKNOWN');
    assert.notEqual(a.domains.IAP.status, 'IDLE');
  });

  test('security leak signal -> SECRET_OR_PII_LEAK CRITICAL + BLOCK', () => {
    const a = evaluate({ events: [], slo: SLO, now: NOW, signals: baseSignals(), iapE2eEvidence: { verified: true }, security: { leak: true, count: 1 } });
    assert.ok(a.alerts.some((x) => x.code === 'SECRET_OR_PII_LEAK' && x.releaseBlocking));
    assert.equal(a.releaseGate.status, 'BLOCK');
  });

  test('NEW -> ONGOING -> RESOLVED lifecycle', () => {
    const breach = [iapEv('iap.credit.granted', { clientRequestId: 'z', creditDelta: 9, txCorrelation: 't:z' })];
    const a1 = run(breach, verified);
    assert.equal(a1.alerts.find((x) => x.code === 'IAP_GRANT_DELTA_NOT_ONE').state, 'NEW');
    const a2 = evaluate({ events: breach, slo: SLO, now: NOW, prev: a1, signals: baseSignals(), iapE2eEvidence: { verified: true } });
    assert.equal(a2.alerts.find((x) => x.code === 'IAP_GRANT_DELTA_NOT_ONE').state, 'ONGOING');
    const a3 = evaluate({ events: [...purchaseOp('a', 't:a')], slo: SLO, now: NOW, prev: a2, signals: baseSignals(), iapE2eEvidence: { verified: true } });
    assert.ok(a3.resolvedAlerts.some((x) => x.code === 'IAP_GRANT_DELTA_NOT_ONE'));
  });

  test('report renders without throwing and contains no obvious PII keys', () => {
    const a = run([...purchaseOp('a', 't:a')], verified);
    const r = renderReport(a);
    assert.ok(r.includes('Runtime Health'));
    for (const bad of ['receipt', 'verificationData', 'password', 'Bearer']) assert.ok(!r.toLowerCase().includes(bad.toLowerCase()));
  });
});
