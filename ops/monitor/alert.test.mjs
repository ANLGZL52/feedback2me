// Alert calibration tests — runtime-only alerting. Run: node --test ops/monitor/alert.test.mjs
// Proves release-readiness signals (CI missing/stale P0, journey UNKNOWN, config/
// build/migration gates) do NOT alert; only a live DOWN component or an open
// runtime incident does. DEGRADED-only does not alert.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { decideAlert } from './alert.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// helpers
const snap = (over = {}) => ({ components: {}, incidents: [], blockers: [], overall: 'UNKNOWN', ...over });
const comp = (m) => Object.fromEntries(Object.entries(m).map(([id, status]) => [id, { status }]));

test('TEST 1: live component DOWN → WOULD ALERT', () => {
  assert.equal(decideAlert(snap({ components: comp({ 'node-firestore': 'DOWN' }) })).alert, true);
});

test('TEST 2: open incident whose component is currently DOWN → WOULD ALERT', () => {
  const s = snap({
    components: comp({ 'node-firestore': 'DOWN' }),
    incidents: [{ id: 'inc-1', componentId: 'node-firestore', status: 'OPEN', severity: 'P1' }],
  });
  assert.equal(decideAlert(s).alert, true);
});

test('TEST 3: release P0 blocker only (no live DOWN) → NO ALERT', () => {
  const s = snap({ blockers: [{ id: 'x', severity: 'P0', releaseBlocking: true, source: 'static-architecture-risk' }] });
  assert.equal(decideAlert(s).alert, false);
});

test('TEST 4: CI-missing P0 blocker → NO ALERT', () => {
  const s = snap({ blockers: [{ id: 'ci-ci-flutter-test', severity: 'P0', releaseBlocking: true, source: 'ci-invariant' }] });
  assert.equal(decideAlert(s).alert, false);
});

test('TEST 5: CI-stale P0 blocker → NO ALERT', () => {
  const s = snap({ blockers: [{ id: 'ci-ci-web-build-stale', severity: 'P0', releaseBlocking: true, source: 'ci-stale' }] });
  assert.equal(decideAlert(s).alert, false);
});

test('TEST 6: P1 blockers only → NO ALERT', () => {
  const s = snap({ blockers: [
    { id: 'build-number-unconfirmed', severity: 'P1', releaseBlocking: true },
    { id: 'ispremium-audit-pending', severity: 'P1', releaseBlocking: true },
  ] });
  assert.equal(decideAlert(s).alert, false);
});

test('TEST 7: journey UNKNOWN (not-verified blocker) → NO ALERT', () => {
  const s = snap({ blockers: [{ id: 'unverified-j-owner-start', severity: 'P1', releaseBlocking: true, source: 'not-verified' }] });
  assert.equal(decideAlert(s).alert, false);
});

test('TEST 8: version-config-document-missing → NO ALERT', () => {
  const s = snap({ blockers: [{ id: 'version-config-document-missing', severity: 'P1', releaseBlocking: true, source: 'live-drift' }] });
  assert.equal(decideAlert(s).alert, false);
});

test('TEST 9: live DEGRADED only → NO ALERT (dashboard-only)', () => {
  const s = snap({ components: comp({ 'node-firestore-rules': 'DEGRADED' }) });
  assert.equal(decideAlert(s).alert, false);
});

test('TEST 9b: DEGRADED component + its OPEN P2 incident → NO ALERT (the key fix)', () => {
  // reconcileIncidents opens a P2 OPEN incident for a DEGRADED component; a blanket
  // "any open incident" trigger would wrongly alert. Component is not DOWN → no alert.
  const s = snap({
    components: comp({ 'node-firestore': 'DEGRADED' }),
    incidents: [{ id: 'inc-deg', componentId: 'node-firestore', status: 'OPEN', severity: 'P2' }],
  });
  assert.equal(decideAlert(s).alert, false);
  assert.equal(decideAlert(s).openIncidentCount, 1);      // incident exists...
  assert.equal(decideAlert(s).alertableIncidentCount, 0); // ...but is NOT alertable
});

test('TEST 9c: OPEN incident but component already recovered to HEALTHY → NO ALERT (stale incident)', () => {
  const s = snap({
    components: comp({ 'node-firestore': 'HEALTHY' }),
    incidents: [{ id: 'inc-stale', componentId: 'node-firestore', status: 'OPEN', severity: 'P1' }],
  });
  assert.equal(decideAlert(s).alert, false);
});

test('TEST 10: existing DOWN + same DOWN → still alerts (runner dedups to one issue, no new issue)', () => {
  // decideAlert returns alert=true; the runner comments on the existing issue
  // instead of opening a new one (dedup by open ops-alert label).
  const s = snap({ components: comp({ 'node-firestore': 'DOWN' }) });
  const d = decideAlert(s);
  assert.equal(d.alert, true);
  assert.deepEqual(d.down, ['node-firestore']);
});

test('TEST 11: previously-DOWN now recovered (no live DOWN, no open incident) → alert=false (runner closes issue)', () => {
  const s = snap({ components: comp({ 'node-firestore': 'HEALTHY' }), incidents: [{ id: 'inc-1', status: 'RESOLVED' }] });
  assert.equal(decideAlert(s).alert, false);
});

test('TEST 8b (regression): REAL current snapshot → alert=false (release-gate P0s are NOT runtime outages)', () => {
  const p = join(__dirname, '..', '..', 'ops-status', 'latest.json');
  let real; try { real = JSON.parse(readFileSync(p, 'utf8')); } catch { real = null; }
  if (!real) return; // snapshot not present in this environment
  const d = decideAlert(real);
  const liveDown = Object.values(real.components || {}).filter((c) => c.status === 'DOWN').length;
  const openInc = (real.incidents || []).filter((i) => i.status === 'OPEN').length;
  // Whatever the release-gate P0 count is, alert must track ONLY live signals.
  assert.equal(d.alert, liveDown > 0 || openInc > 0);
  if (liveDown === 0 && openInc === 0) assert.equal(d.alert, false);
});
