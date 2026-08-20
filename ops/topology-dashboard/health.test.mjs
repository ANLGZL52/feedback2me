// End-to-end health engine tests. Deterministic; no network. Every case encodes a Mission-11
// invariant: IDLE ≠ unhealthy, N/A ≠ healthy, money-safety dominates, collector-blind semantics,
// deferred IAP E2E never marks runtime unhealthy, release gate stays separate from runtime.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { resolveNode, criticalPaths, moneySafety, overallSystemHealth, coverage, buildSystem } from './server/health-model.mjs';

// ---- fixtures ----
const baseline = () => ({
  health: {
    generatedAt: '2026-08-20T15:00:00Z', currentRuntimeHealth: 'HEALTHY', observabilityPlatformStatus: 'FULL',
    runtimeValidationStatus: 'PARTIAL', productReleaseGate: { status: 'WARN' },
    validationEvidence: { realIapE2E: 'DEFERRED' }, collectorFreshness: { ageMinutes: 5 },
    domains: { IAP: { status: 'IDLE' }, OPENAI: { status: 'IDLE' }, RAILWAY: { status: 'IDLE' }, POSTGRES: { status: 'HEALTHY' }, COLLECTOR: { status: 'HEALTHY' }, SECURITY: { status: 'HEALTHY' }, SERVICE: { status: 'HEALTHY' } },
  },
  latest: { components: {
    'node-firestore': { status: 'HEALTHY' }, 'node-railway-api': { status: 'HEALTHY' }, 'node-postgres': { status: 'HEALTHY' },
    'node-firebase-auth': { status: 'UNKNOWN' }, 'node-cloud-functions': { status: 'UNKNOWN' }, 'node-ai-proxy': { status: 'UNKNOWN' },
    'node-apple-store': { status: 'UNKNOWN' }, 'node-openai': { status: 'UNKNOWN' },
  } },
  incidentState: { incidents: [] },
  incidentActions: { mode: 'LIVE', deliveryHealth: { deliveryMode: 'LIVE', deliveryHealth: 'IDLE' } },
  digestDelivery: { channel: 'slack', health: 'IDLE' },
});
const withMoneyViolation = () => { const a = baseline(); a.incidentState.incidents = [{ code: 'IAP_GRANT_DELTA_NOT_ONE', domain: 'IAP', state: 'OPEN', issueNumber: 7 }]; a.health.domains.IAP.status = 'UNHEALTHY'; return a; };
const withPgCritical = () => { const a = baseline(); a.latest.components['node-postgres'].status = 'UNHEALTHY'; a.health.domains.POSTGRES.status = 'UNHEALTHY'; a.health.currentRuntimeHealth = 'UNHEALTHY'; return a; };
const withCollectorBlind = () => { const a = baseline(); a.health.domains.COLLECTOR.status = 'UNKNOWN'; return a; };

describe('resolveNode — evidence-based, no fabrication', () => {
  test('firestore closes N/A → HEALTHY from the real blackbox component', () => {
    const r = resolveNode('firestore', baseline());
    assert.equal(r.serviceHealth, 'HEALTHY'); assert.equal(r.severity, 'green'); assert.equal(r.probe, true);
  });
  test('railway is HEALTHY (component /health) with traffic IDLE — service ≠ traffic', () => {
    const r = resolveNode('railway', baseline());
    assert.equal(r.serviceHealth, 'HEALTHY'); assert.equal(r.trafficState, 'IDLE (no traffic)');
  });
  test('OpenAI IDLE is NOT unhealthy (observable, no traffic)', () => {
    const r = resolveNode('openai', baseline());
    assert.equal(r.serviceHealth, 'IDLE'); assert.notEqual(r.severity, 'red');
  });
  test('N/A node (Flutter client) is NOT healthy and carries a reason', () => {
    const r = resolveNode('flutter_app', baseline());
    assert.equal(r.serviceHealth, 'N/A'); assert.equal(r.observable, false); assert.ok(r.naReason);
  });
  test('firebase_auth stays UNKNOWN (not fabricated green) but a canary can upgrade it', () => {
    assert.equal(resolveNode('firebase_auth', baseline()).serviceHealth, 'UNKNOWN');
    const withCanary = resolveNode('firebase_auth', baseline(), { CANARY_AUTH: { status: 'HEALTHY' } });
    assert.equal(withCanary.serviceHealth, 'HEALTHY');
  });
  test('deferred E2E node reports DEFERRED and is flagged separate=release', () => {
    const r = resolveNode('real_iap_e2e', baseline());
    assert.equal(r.serviceHealth, 'DEFERRED'); assert.equal(r.separate, 'release');
  });
});

describe('money-safety business health', () => {
  test('no violations → HEALTHY; real IAP E2E stays DEFERRED', () => {
    const ms = moneySafety(baseline()); assert.equal(ms.status, 'HEALTHY'); assert.equal(ms.realIapE2E, 'DEFERRED');
  });
  test('an open money-safety incident → UNHEALTHY with the code', () => {
    const ms = moneySafety(withMoneyViolation()); assert.equal(ms.status, 'UNHEALTHY'); assert.ok(ms.violations.includes('IAP_GRANT_DELTA_NOT_ONE'));
  });
});

describe('critical paths', () => {
  test('FEEDBACK path HEALTHY (firestore+railway+service real), AUTH PARTIAL (auth UNKNOWN + client N/A)', () => {
    const paths = criticalPaths(baseline());
    const feedback = paths.find((p) => p.id === 'FEEDBACK'); assert.equal(feedback.status, 'HEALTHY');
    const auth = paths.find((p) => p.id === 'AUTH'); assert.ok(['PARTIAL', 'UNKNOWN'].includes(auth.status));
  });
  test('IAP path PARTIAL at baseline (Apple external UNKNOWN + real ledgers HEALTHY), UNHEALTHY on money-safety violation', () => {
    assert.equal(criticalPaths(baseline()).find((p) => p.id === 'IAP').status, 'PARTIAL');
    assert.equal(criticalPaths(withMoneyViolation()).find((p) => p.id === 'IAP').status, 'UNHEALTHY');
  });
  test('IDLE members never make a path unhealthy', () => {
    const ai = criticalPaths(baseline()).find((p) => p.id === 'AI'); // openai IDLE + ai_summary UNKNOWN
    assert.notEqual(ai.status, 'UNHEALTHY');
  });
});

describe('overall system health (dominance rules)', () => {
  test('baseline → HEALTHY (gate WARN & E2E DEFERRED do NOT downgrade runtime)', () => {
    const o = overallSystemHealth(baseline());
    assert.equal(o.status, 'HEALTHY');
    assert.equal(o.releaseGate, 'WARN'); assert.equal(o.realIapE2E, 'DEFERRED'); assert.equal(o.runtimeValidation, 'PARTIAL');
  });
  test('money-safety violation DOMINATES → UNHEALTHY with reason + incident', () => {
    const o = overallSystemHealth(withMoneyViolation());
    assert.equal(o.status, 'UNHEALTHY');
    const r = o.reasons.find((x) => x.node === 'iap_verify'); assert.ok(r); assert.equal(r.incident && r.incident.issueNumber, 7);
  });
  test('Postgres critical DOMINATES → UNHEALTHY, affected paths surfaced', () => {
    const o = overallSystemHealth(withPgCritical());
    assert.equal(o.status, 'UNHEALTHY'); assert.ok(o.reasons.some((r) => r.node === 'postgres'));
  });
  test('collector blind (UNKNOWN) → DEGRADED (observability), NOT runtime UNHEALTHY', () => {
    const o = overallSystemHealth(withCollectorBlind());
    assert.equal(o.status, 'DEGRADED'); assert.ok(o.reasons.some((r) => r.node === 'collector'));
  });
  test('deferred IAP E2E alone never marks runtime UNHEALTHY', () => {
    const a = baseline(); // E2E already DEFERRED
    assert.equal(overallSystemHealth(a).status, 'HEALTHY');
  });
});

describe('coverage + system payload', () => {
  test('coverage counts are derived, not fabricated', () => {
    const c = coverage(baseline());
    assert.equal(c.total, 27);
    assert.ok(c.observable > 0 && c.observable <= c.total);
    assert.ok(c.probed > 0 && c.probed <= c.total);
    assert.equal(c.criticalPaths.total, 5);
    assert.ok(c.criticalPaths.covered >= 1 && c.criticalPaths.covered <= 5);
  });
  test('N/A nodes are excluded from observable (N/A ≠ healthy ≠ observable)', () => {
    const c = coverage(baseline());
    assert.ok(c.observable < c.total, 'some client/external nodes remain N/A');
  });
  test('buildSystem returns overall + paths + coverage + canary slots', () => {
    const s = buildSystem(baseline());
    assert.equal(s.overall, 'HEALTHY'); assert.equal(s.paths.length, 5); assert.ok(s.coverage);
    assert.equal(s.moneySafety, 'HEALTHY'); assert.equal(s.realIapE2E, 'DEFERRED');
  });
  test('a run canary is reflected in the system payload', () => {
    const s = buildSystem(baseline(), { __runAt: '2026-08-20T15:10:00Z', CANARY_AUTH: { status: 'HEALTHY', node: 'firebase_auth', detail: 'ok', desc: 'x' } });
    assert.equal(s.canaryRunAt, '2026-08-20T15:10:00Z'); assert.ok(s.canaries.find((c) => c.id === 'CANARY_AUTH'));
  });
});
