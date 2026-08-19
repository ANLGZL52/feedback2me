// Observability V6 — daily digest tests. Deterministic (fixed UTC epochs; no Date.now).
// Run: node --test ops/monitor/digest.test.mjs
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { computeDigestSchedule, renderDigestData, renderDigest, renderDigestText, deliverDigest, shouldDeliverDigest, nullDigestAdapter, windowKey, DIGEST_HOUR_UTC } from './digest.mjs';
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

describe('digest text renderer (Phase 6)', () => {
  const d = renderDigestData({ health: health(), incidents: [], actions: null, schedule: computeDigestSchedule(AFTER, {}), now: AFTER });
  const txt = renderDigestText(d);
  test('concise + no PII + has key lines', () => {
    assert.ok(txt.includes('Feedback2Me — Daily Ops Digest'));
    assert.ok(txt.includes('Runtime: HEALTHY'));
    assert.ok(txt.includes('Real IAP E2E: DEFERRED'));
    assert.equal(validateIssuePayload('slack', txt).safe, true);
    assert.ok(txt.length < 1200, 'digest text should be phone-readable');
  });
});

describe('digest delivery eligibility (shouldDeliverDigest, Phase 11)', () => {
  const sched = computeDigestSchedule(AFTER, {});
  test('disabled -> no send', () => assert.equal(shouldDeliverDigest(sched, {}, { enabled: false }).send, false));
  test('dry-run -> no send', () => assert.equal(shouldDeliverDigest(sched, {}, { enabled: true, dryRun: true, configured: true }).send, false));
  test('not configured -> no send', () => assert.equal(shouldDeliverDigest(sched, {}, { enabled: true, dryRun: false, configured: false }).reason, 'not_configured'));
  test('due + enabled + configured -> send', () => assert.equal(shouldDeliverDigest(sched, {}, { enabled: true, dryRun: false, configured: true }).send, true));
  test('already delivered this window -> no send', () => assert.equal(shouldDeliverDigest(sched, { lastDigestDeliveredWindow: '2026-08-19' }, { enabled: true, dryRun: false, configured: true }).reason, 'already_delivered'));
});

describe('digest delivery state machine (deliverDigest, async)', () => {
  const d = renderDigestData({ health: health(), incidents: [], actions: null, schedule: computeDigestSchedule(AFTER, {}), now: AFTER });
  const sched = computeDigestSchedule(AFTER, {});
  const okAdapter = { name: 'slack', configured: true, send: async () => ({ ok: true, status: 200, latencyMs: 12 }) };
  test('disabled -> DISABLED, not delivered', async () => {
    const r = await deliverDigest(nullDigestAdapter, d, { enabled: false, dryRun: true, schedule: sched });
    assert.equal(r.delivered, false); assert.equal(r.mode, 'DISABLED');
  });
  test('enabled + dry-run -> DRY_RUN, not delivered', async () => {
    assert.equal((await deliverDigest(okAdapter, d, { enabled: true, dryRun: true, schedule: sched })).mode, 'DRY_RUN');
  });
  test('enabled + live + NOT configured -> NOT_CONFIGURED, 0 sent', async () => {
    const r = await deliverDigest(nullDigestAdapter, d, { enabled: true, dryRun: false, schedule: sched });
    assert.equal(r.health, 'NOT_CONFIGURED'); assert.equal(r.delivered, false); assert.equal(r.event, 'digest.delivery.not_configured');
  });
  test('enabled + live + configured + due -> HEALTHY, delivered', async () => {
    const r = await deliverDigest(okAdapter, d, { enabled: true, dryRun: false, schedule: sched, state: {}, now: AFTER });
    assert.equal(r.delivered, true); assert.equal(r.health, 'HEALTHY'); assert.equal(r.event, 'digest.delivery.sent'); assert.equal(r.statusCode, 200);
  });
  test('already delivered this window -> IDLE skip, 0 sent', async () => {
    const r = await deliverDigest(okAdapter, d, { enabled: true, dryRun: false, schedule: computeDigestSchedule(AFTER, { lastDigestDeliveredWindow: '2026-08-19' }), state: { lastDigestDeliveredWindow: '2026-08-19' } });
    assert.equal(r.delivered, false); assert.equal(r.event, 'digest.delivery.skipped');
  });
  test('unsafe payload -> DIGEST_DELIVERY_PAYLOAD_REJECTED, not sent', async () => {
    let sent = 0; const spy = { name: 'slack', configured: true, send: async () => { sent++; return { ok: true }; } };
    const leaky = renderDigestData({ health: health({ deploymentContext: { commit: 'leak a@b.com', build: '22' } }), incidents: [], actions: null, schedule: sched, now: AFTER });
    const r = await deliverDigest(spy, leaky, { enabled: true, dryRun: false, schedule: sched, state: {}, now: AFTER });
    assert.equal(r.code, 'DIGEST_DELIVERY_PAYLOAD_REJECTED'); assert.equal(r.delivered, false); assert.equal(sent, 0);
  });
  test('transport 500 -> UNAVAILABLE, DIGEST_DELIVERY_FAILED', async () => {
    const bad = { name: 'slack', configured: true, send: async () => ({ ok: false, status: 500, latencyMs: 5 }) };
    const r = await deliverDigest(bad, d, { enabled: true, dryRun: false, schedule: sched, state: {}, now: AFTER });
    assert.equal(r.health, 'UNAVAILABLE'); assert.equal(r.code, 'DIGEST_DELIVERY_FAILED'); assert.equal(r.delivered, false);
  });
  test('windowKey is a UTC date string', () => assert.equal(windowKey(AFTER), '2026-08-19'));
});
