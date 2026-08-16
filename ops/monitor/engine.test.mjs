// Ops health engine tests. Run: node --test ops/monitor/engine.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import {
  computeJourneys, computeOverall, journeyStatus, edgeStatus, applyCheckResult,
  reconcileIncidents, releaseBlockers, releaseReadiness, buildSnapshot, platformReadiness,
} from './engine.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const policy = JSON.parse(readFileSync(join(__dirname, '..', 'checks', 'health-policy.json'), 'utf8'));
const graph = JSON.parse(readFileSync(join(__dirname, '..', '..', 'docs', 'architecture', 'dependency-graph.json'), 'utf8'));
const th = policy.thresholds;

function allHealthy() {
  const m = {};
  for (const j of Object.values(policy.journeys))
    for (const id of [...(j.hardDeps || []), ...(j.softDeps || []), ...(j.fallbackGroups || []).flatMap((g) => [g.primary, ...(g.alternates || [])])])
      m[id] = 'HEALTHY';
  return m;
}

test('edgeStatus derivation', () => {
  assert.equal(edgeStatus('HEALTHY', 'HEALTHY'), 'HEALTHY');
  assert.equal(edgeStatus('HEALTHY', 'DOWN'), 'DOWN');
  assert.equal(edgeStatus('DEGRADED', 'HEALTHY'), 'DEGRADED');
  assert.equal(edgeStatus('HEALTHY', 'UNKNOWN'), 'UNKNOWN');
});

test('all healthy → critical journeys HEALTHY, overall HEALTHY (IAP no longer capped)', () => {
  const cs = allHealthy();
  const j = computeJourneys(cs, policy);
  for (const c of policy.criticalJourneys) assert.equal(j[c].status, 'HEALTHY', c);
  assert.equal(computeOverall(j, policy.criticalJourneys), 'HEALTHY');
  // IAP server-verification restored: no static risk caps purchase-credit anymore.
  assert.equal(j['j-purchase-credit'].status, 'HEALTHY');
  assert.equal(j['j-purchase-credit'].staticRisk, null);
});

test('Firebase Auth DOWN → path-based: owner/create DOWN, public-feedback HEALTHY', () => {
  const cs = { ...allHealthy(), 'node-firebase-auth': 'DOWN' };
  const j = computeJourneys(cs, policy);
  assert.equal(j['j-owner-start'].status, 'DOWN');
  assert.equal(j['j-create-demo'].status, 'DOWN');
  assert.equal(j['j-create-premium'].status, 'DOWN');
  assert.equal(j['j-public-feedback'].status, 'HEALTHY'); // does NOT depend on auth
  assert.equal(computeOverall(j, policy.criticalJourneys), 'CRITICAL');
});

test('Firestore DOWN with Railway UP → public-feedback DEGRADED (fallback available), not DOWN', () => {
  const cs = { ...allHealthy(), 'node-firestore': 'DOWN', 'node-railway-api': 'HEALTHY' };
  const j = computeJourneys(cs, policy);
  assert.equal(j['j-public-feedback'].status, 'DEGRADED');
  assert.equal(j['j-public-feedback'].fallbackUsed, true);
});

test('Firestore DOWN with Railway also DOWN → public-feedback DOWN', () => {
  const cs = { ...allHealthy(), 'node-firestore': 'DOWN', 'node-railway-api': 'DOWN', 'node-postgres': 'DOWN' };
  const j = computeJourneys(cs, policy);
  assert.equal(j['j-public-feedback'].status, 'DOWN');
});

test('OpenAI DOWN → ai-summary DEGRADED (soft, heuristic fallback), not DOWN, overall unaffected', () => {
  const cs = { ...allHealthy(), 'node-openai': 'DOWN', 'node-ai-proxy': 'DOWN' };
  const j = computeJourneys(cs, policy);
  assert.equal(j['j-ai-summary'].status, 'DEGRADED');
  assert.equal(computeOverall(j, policy.criticalJourneys), 'HEALTHY'); // ai-summary not critical
});

test('PostgreSQL DOWN (Firestore default) → public-feedback HEALTHY, rest journey DOWN but non-critical', () => {
  const cs = { ...allHealthy(), 'node-postgres': 'DOWN' };
  const j = computeJourneys(cs, policy);
  assert.equal(j['j-public-feedback'].status, 'HEALTHY');
  assert.equal(j['j-public-feedback-rest'].status, 'DOWN');
  assert.notEqual(computeOverall(j, policy.criticalJourneys), 'CRITICAL');
});

test('UNKNOWN deps → journey UNKNOWN (no fake health)', () => {
  const j = journeyStatus({}, policy.journeys['j-owner-start'], policy);
  assert.equal(j.status, 'UNKNOWN');
});

test('incident threshold state machine: 1 fail → DEGRADED, 2 → DOWN, recovery 2 → HEALTHY', () => {
  let st = { status: 'HEALTHY', consecutiveFail: 0, consecutiveOk: 2 };
  st = applyCheckResult(st, { status: 'DOWN', ts: 't1' }, th);
  assert.equal(st.status, 'DEGRADED');
  st = applyCheckResult(st, { status: 'DOWN', ts: 't2' }, th);
  assert.equal(st.status, 'DOWN');
  st = applyCheckResult(st, { status: 'HEALTHY', ts: 't3' }, th);
  assert.equal(st.status, 'DEGRADED'); // recovering
  st = applyCheckResult(st, { status: 'HEALTHY', ts: 't4' }, th);
  assert.equal(st.status, 'HEALTHY');
});

test('UNKNOWN → HEALTHY is immediate (no recovery gating from not-observed)', () => {
  const st = applyCheckResult({ status: 'UNKNOWN', consecutiveOk: 0 }, { status: 'HEALTHY', ts: 't' }, th);
  assert.equal(st.status, 'HEALTHY');
});

test('P0 invariant → immediate DOWN (skips threshold)', () => {
  const st = applyCheckResult({ status: 'HEALTHY', consecutiveFail: 0 }, { status: 'DOWN', ts: 't', severity: 'P0' }, th);
  assert.equal(st.status, 'DOWN');
});

test('UNKNOWN check result does not fabricate health', () => {
  const st = applyCheckResult({ status: 'HEALTHY' }, { status: 'UNKNOWN', ts: 't' }, th);
  assert.equal(st.status, 'UNKNOWN');
});

test('incidents open on DOWN and resolve on recovery', () => {
  let inc = reconcileIncidents([], { 'node-firestore': { status: 'DOWN', lastFailure: 't1' } }, policy, { ts: 't1', runId: 'r1' });
  assert.equal(inc.filter((i) => i.status === 'OPEN').length, 1);
  assert.ok(inc[0].journeys.includes('j-public-feedback'));
  inc = reconcileIncidents(inc, { 'node-firestore': { status: 'HEALTHY', lastGood: 't2' } }, policy, { ts: 't2' });
  assert.equal(inc.filter((i) => i.status === 'OPEN').length, 0);
  assert.equal(inc[0].status, 'RESOLVED');
});

test('release gate: IAP P0 removed — no P0 blocker under all-healthy + fresh CI (P1 manual gates remain)', () => {
  const cs = allHealthy();
  const ci = {}, cur = {};
  for (const inv of policy.releaseGate.requiredCiInvariants) { ci[inv] = { status: 'PASS', scopeHash: 'h-' + inv }; cur[inv] = 'h-' + inv; }
  const snap = buildSnapshot({ componentStates: Object.fromEntries(Object.entries(cs).map(([k, v]) => [k, { status: v }])), edges: graph.edges, policy, incidents: [], ciEvidence: ci, meta: { environment: 'production', currentScopeHashes: cur } });
  const b = snap.blockers;
  // The former P0 IAP static blocker is gone (server verification restored + code-verified).
  assert.ok(!b.some((x) => x.id === 'iap-client-direct-credit'), 'former IAP P0 static blocker removed');
  const rr = releaseReadiness(snap, policy);
  assert.equal(rr.p0Blockers.length, 0, 'no P0 blockers under all-healthy + fresh CI');
  // Release is still gated — now only by the P1 manual items (build number, isPremium audit).
  assert.ok(rr.p1Blockers.some((x) => x.id === 'build-number-unconfirmed'));
  assert.ok(rr.p1Blockers.some((x) => x.id === 'ispremium-audit-pending'));
  assert.equal(rr.verdict, 'NOT READY');
  assert.equal(rr.exitCode, 1);
  assert.equal(rr.readyForIOS, false);
});

test('release gate: missing CI invariant is a P0 blocker', () => {
  const b = releaseBlockers(policy, {}, {}); // no ci evidence
  assert.ok(b.some((x) => x.source === 'ci-invariant' && x.severity === 'P0'));
});

test('release gate: release-critical UNKNOWN journey blocks (P1, not-verified)', () => {
  const b = releaseBlockers(policy, { 'j-purchase-credit': { status: 'UNKNOWN' } }, {});
  assert.ok(b.some((x) => x.source === 'not-verified' && x.id.includes('j-purchase-credit')));
});

test('release gate: static P1 gates (build-number, ispremium) are blockers', () => {
  const b = releaseBlockers(policy, {}, {});
  assert.ok(b.some((x) => x.id === 'build-number-unconfirmed' && x.severity === 'P1'));
  assert.ok(b.some((x) => x.id === 'ispremium-audit-pending' && x.severity === 'P1'));
});

test('live drift: firestore-rules DEGRADED + RULES_DENY triggers appconfig-rule-drift P1', () => {
  const b = releaseBlockers(policy, {}, {}, {
    componentStatus: { 'node-firestore-rules': 'DEGRADED' },
    componentErrorCodes: { 'node-firestore-rules': 'RULES_DENY' },
  });
  assert.ok(b.some((x) => x.id === 'appconfig-rule-drift' && x.severity === 'P1'));
});

test('live drift: APPCONFIG_MISSING does NOT fire appconfig-rule-drift (rules OK, doc missing)', () => {
  const b = releaseBlockers(policy, {}, {}, {
    componentStatus: { 'node-firestore-rules': 'HEALTHY', 'node-version-gate-svc': 'HEALTHY' },
    componentErrorCodes: { 'node-firestore-rules': 'APPCONFIG_MISSING', 'node-version-gate-svc': 'APPCONFIG_MISSING' },
  });
  assert.ok(!b.some((x) => x.id === 'appconfig-rule-drift'), 'rule-drift must NOT fire on APPCONFIG_MISSING');
});

test('live config: APPCONFIG_MISSING triggers version-config-document-missing P1 (even when HEALTHY)', () => {
  const b = releaseBlockers(policy, {}, {}, {
    componentStatus: { 'node-version-gate-svc': 'HEALTHY' },
    componentErrorCodes: { 'node-version-gate-svc': 'APPCONFIG_MISSING' },
  });
  const m = b.find((x) => x.id === 'version-config-document-missing');
  assert.ok(m && m.severity === 'P1' && m.releaseBlocking === true);
});

test('scoped freshness: matching scopeHash = FRESH (no stale blocker)', () => {
  const ci = {}, cur = {};
  for (const inv of policy.releaseGate.requiredCiInvariants) { ci[inv] = { status: 'PASS', scopeHash: 'h-' + inv }; cur[inv] = 'h-' + inv; }
  const b = releaseBlockers(policy, {}, ci, { currentScopeHashes: cur });
  assert.equal(b.filter((x) => x.source === 'ci-stale').length, 0);
});
test('scoped freshness: changed scopeHash = STALE (even at same/other commit)', () => {
  const ci = {}, cur = {};
  for (const inv of policy.releaseGate.requiredCiInvariants) { ci[inv] = { status: 'PASS', scopeHash: 'old' }; cur[inv] = 'new'; }
  const b = releaseBlockers(policy, {}, ci, { currentScopeHashes: cur });
  assert.ok(b.some((x) => x.source === 'ci-stale'));
});
test('scoped freshness: legacy evidence without scopeHash = STALE (re-verify)', () => {
  const ci = {}, cur = {};
  for (const inv of policy.releaseGate.requiredCiInvariants) { ci[inv] = { status: 'PASS' }; cur[inv] = 'x'; }
  const b = releaseBlockers(policy, {}, ci, { currentScopeHashes: cur });
  assert.ok(b.some((x) => x.source === 'ci-stale'));
});

test('P1 with releaseBlocking=true BLOCKS (exit 1) — the Problem-1 fix', () => {
  const snap = { blockers: [{ id: 'g', severity: 'P1', releaseBlocking: true, platforms: ['ios', 'android'] }] };
  const rr = releaseReadiness(snap, policy);
  assert.equal(rr.exitCode, 1);
  assert.equal(rr.verdict, 'NOT READY');
  assert.equal(rr.readyForIOS, false);
});
test('releaseBlocking=false is a WARNING not a blocker (READY WITH WARNINGS, exit 0)', () => {
  const snap = { blockers: [{ id: 'w', severity: 'P2', releaseBlocking: false, platforms: ['ios', 'android'] }] };
  const rr = releaseReadiness(snap, policy);
  assert.equal(rr.exitCode, 0);
  assert.equal(rr.verdict, 'READY WITH WARNINGS');
  assert.equal(rr.warnings.length, 1);
});
test('blocker dedupe: no duplicate ids in the computed list', () => {
  const b = releaseBlockers(policy, {}, {});
  const ids = b.map((x) => x.id);
  assert.equal(ids.length, new Set(ids).size);
});

test('platform readiness: store-scoped blocking item hits only its platform', () => {
  const snap = { blockers: [{ id: 'apple-x', severity: 'P0', releaseBlocking: true, platforms: ['ios'] }] };
  const pr = platformReadiness(snap, policy);
  assert.equal(pr.ios.ready, false);
  assert.equal(pr.android.ready, true);
});
