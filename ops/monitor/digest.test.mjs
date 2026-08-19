// Observability V6 — daily digest tests. Deterministic (fixed UTC epochs; no Date.now).
// Run: node --test ops/monitor/digest.test.mjs
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { computeDigestSchedule, renderDigestData, renderDigest, deliverDigest, nullDigestAdapter, windowKey, DIGEST_HOUR_UTC } from './digest.mjs';
import { validateIssuePayload } from './incident-actions.mjs';

const AT = (iso) => Date.parse(iso);
const BEFORE = AT('2026-08-19T06:00:00Z'); // before 07:00 UTC window
const AFTER = AT('2026-08-19T08:00:00Z');  // after window
const NEXTDAY = AT('2026-08-20T08:00:00Z');

const health = (over = {}) => ({
  generatedAt: new Date(AFTER).toISOString(), currentRuntimeHealth: 'HEALTHY', observabilityPlatformStatus: 'FULL',
  runtimeValidationStatus: 'PARTIAL', productReleaseGate: { status: 'WARN' }, deploymentContext: { commit: 'd4be199', build: '22' },
  domains: { IAP: { status: 'HEALTHY' }, OPENAI: { status: 'IDLE' }, RAILWAY: { status: 'HEALTHY' }, POSTGRES: { status: 'HEALTHY' }, COLLECTOR: { status: 'HEALTHY' }, SERVICE: { status: 'HEALTHY' } },
  trends: { iapVerifyFailures: 'STABLE', openaiFailures: 'INSUFFICIENT_DATA' },
  deferredValidations: [{ id: 'REAL_IAP_TESTFLIGHT_E2E', status: 'DEFERRED' }],
  validationEvidence: { realIapE2E: 'DEFERRED' }, collectorFreshness: { ageMinutes: 5 }, ...over,
});
const inc = (o) => ({ incidentId: `${o.domain}:${o.code}`, state: 'OPEN', startedAt: new Date(AFTER - 3600000).toISOString(), resolvedAt: null, durationMs: 3600000, flapping: false, issueNumber: null, ...o });

describe('digest scheduling (deterministic, once/UTC-day)', () => {
  test('before delivery hour -> not due', () => {
    const s = computeDigestSchedule(BEFORE, {});
    assert.equal(s.due, false); assert.equal(s.reason, 'before_delivery_window');
  });
  test('after hour, never delivered -> due', () => {
    const s = computeDigestSchedule(AFTER, {});
    assert.equal(s.due, true); assert.equal(s.reason, 'eligible'); assert.equal(s.window, '2026-08-19');
  });
  test('already delivered this window -> not due (repeat run same window)', () => {
    const s = computeDigestSchedule(AFTER, { lastDigestDeliveredWindow: '2026-08-19' });
    assert.equal(s.due, false); assert.equal(s.reason, 'already_delivered_this_window');
  });
  test('next day after hour -> due again (new window)', () => {
    const s = computeDigestSchedule(NEXTDAY, { lastDigestDeliveredWindow: '2026-08-19' });
    assert.equal(s.due, true); assert.equal(s.window, '2026-08-20');
  });
  test('nextEligibleAt is at the delivery hour UTC', () => {
    assert.ok(computeDigestSchedule(BEFORE, {}).nextEligibleAt.endsWith(`T0${DIGEST_HOUR_UTC}:00:00.000Z`));
  });
});

describe('digest data model', () => {
  const sched = computeDigestSchedule(AFTER, {});
  test('healthy 24h -> zero incident counts', () => {
    const d = renderDigestData({ health: health(), incidents: [], actions: null, schedule: sched, now: AFTER });
    assert.deepEqual(d.incidentCounts, { opened: 0, resolved: 0, active: 0, flapping: 0 });
    assert.equal(d.runtimeStatus, 'HEALTHY'); assert.equal(d.realIapE2E, 'DEFERRED');
  });
  test('opened + resolved + active + flapping counted within 24h', () => {
    const incidents = [
      inc({ domain: 'IAP', code: 'IAP_VERIFY_DOWN', flapping: true }),
      inc({ domain: 'POSTGRES', code: 'POSTGRES_CRITICAL', state: 'RESOLVED', resolvedAt: new Date(AFTER - 600000).toISOString() }),
    ];
    const d = renderDigestData({ health: health(), incidents, actions: null, schedule: sched, now: AFTER });
    assert.equal(d.incidentCounts.opened, 2);
    assert.equal(d.incidentCounts.resolved, 1);
    assert.equal(d.incidentCounts.active, 1);
    assert.equal(d.incidentCounts.flapping, 1);
  });
  test('delivery failure surfaced from actions.deliveryHealth', () => {
    const d = renderDigestData({ health: health(), incidents: [], actions: { deliveryHealth: { deliveryMode: 'LIVE', deliveryHealth: 'DEGRADED', deliveryFailuresWindow: 2, deliveryTransportErrors: 2 } }, schedule: sched, now: AFTER });
    assert.equal(d.deliveryHealth.failures, 2); assert.equal(d.deliveryHealth.health, 'DEGRADED');
  });
  test('no-traffic / missing baseline trends pass through (no crash)', () => {
    const d = renderDigestData({ health: health({ trends: { openaiFailures: 'INSUFFICIENT_DATA' } }), incidents: [], actions: null, schedule: sched, now: AFTER });
    assert.equal(d.trends.openaiFailures, 'INSUFFICIENT_DATA');
  });
});

describe('digest rendering + safety', () => {
  const d = renderDigestData({ health: health(), incidents: [inc({ domain: 'IAP', code: 'IAP_VERIFY_DOWN' })], actions: null, schedule: computeDigestSchedule(AFTER, {}), now: AFTER });
  const md = renderDigest(d);
  test('markdown has the required sections', () => {
    for (const h of ['Daily Ops Digest', 'Incidents (24h)', 'Incident delivery', 'Domain health', '24h trends', 'Deferred validations']) assert.ok(md.includes(h), `missing section: ${h}`);
  });
  test('digest body contains no PII/secret markers', () => assert.equal(validateIssuePayload('digest', md).safe, true));
});

describe('digest delivery abstraction (external delivery OFF in V6)', () => {
  const d = renderDigestData({ health: health(), incidents: [], actions: null, schedule: computeDigestSchedule(AFTER, {}), now: AFTER });
  test('disabled -> not delivered', () => {
    const r = deliverDigest(nullDigestAdapter, d, { enabled: false, dryRun: true });
    assert.equal(r.delivered, false); assert.equal(r.mode, 'DRY_RUN');
  });
  test('enabled but dry-run -> not delivered', () => {
    assert.equal(deliverDigest(nullDigestAdapter, d, { enabled: true, dryRun: true }).delivered, false);
  });
  test('enabled + not dry-run + null adapter -> attempts but nothing sent (no transport)', () => {
    const r = deliverDigest(nullDigestAdapter, d, { enabled: true, dryRun: false });
    assert.equal(r.mode, 'LIVE'); assert.equal(r.delivered, false); // null adapter returns ok:false
  });
  test('enabled + not dry-run + working adapter -> delivered', () => {
    const adapter = { name: 'test', send: () => ({ ok: true }) };
    assert.equal(deliverDigest(adapter, d, { enabled: true, dryRun: false }).delivered, true);
  });
  test('windowKey is a UTC date string', () => assert.equal(windowKey(AFTER), '2026-08-19'));
});
