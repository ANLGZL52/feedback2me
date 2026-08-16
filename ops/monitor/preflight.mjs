#!/usr/bin/env node
// Feedback2Me RELEASE PREFLIGHT. Combines the latest health snapshot + CI evidence
// + static architecture risks into a GO/NO-GO gate. Does NOT deploy, write, or
// touch production.
//
// EXIT CODES (distinct so the observability workflow can tell a release verdict
// from a real execution error — see .github/workflows/ops-health.yml):
//   0  = READY            (release readiness verdict)
//   1  = NOT READY        (release readiness verdict — a VALID computed result,
//                          NOT a monitoring failure; blockers remain honest)
//   2  = EXECUTION ERROR  (no snapshot / unreadable / crash — a real failure)
// Optional arg: a snapshot path (defaults to ops-status/latest.json) for testing.
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { releaseReadiness } from './engine.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = join(__dirname, '..', '..');

let policy, snap, rr;
try {
  policy = JSON.parse(readFileSync(join(REPO, 'ops', 'checks', 'health-policy.json'), 'utf8'));
  const latestPath = process.argv[2] || join(REPO, 'ops-status', 'latest.json');
  if (!existsSync(latestPath)) {
    console.error('NO SNAPSHOT — run `node ops/monitor/run.mjs` first.');
    process.exit(2); // execution error, NOT a readiness verdict
  }
  snap = JSON.parse(readFileSync(latestPath, 'utf8'));
  rr = releaseReadiness(snap, policy);
} catch (e) {
  console.error('PREFLIGHT EXECUTION ERROR: ' + (e && e.message));
  process.exit(2);
}

const S = (v) => (v == null ? 'UNKNOWN' : v);
const ci = snap.ciEvidence || {};
const line = (label, val) => `  ${label.padEnd(26)} ${val}`;

const mark = (s) => (s === 'PASS' || s === 'HEALTHY' ? '✓' : s === 'DEGRADED' ? '!' : s === 'UNKNOWN' || s == null ? '?' : '✗');
console.log('\n=== FEEDBACK2ME RELEASE CONTROL ===');
console.log(`  Snapshot ${snap.generatedAt}  env=${snap.environment}  release=${S(snap.release)}  build=${S(snap.build)}  minSupported=${S(snap.minSupportedBuild)}`);

const staleSet = new Set((snap.blockers || []).filter((b) => b.source === 'ci-stale').map((b) => b.id));
console.log('\n  CI (PASS + scope-fresh; scoped fingerprint, not whole-repo HEAD):');
for (const inv of policy.releaseGate.requiredCiInvariants) {
  const e = ci[inv]; const st = (e && e.status) || 'UNKNOWN';
  const stale = staleSet.has(`ci-${inv}-stale`) ? ' (STALE — scope changed)' : (st === 'PASS' ? ' (fresh)' : '');
  console.log(`   ${mark(stale.includes('STALE') ? 'DEGRADED' : st)} ${inv.padEnd(26)} ${st}${stale}`);
}
console.log('\n  LIVE (read-only production):');
const liveComp = ['node-firebase-hosting', 'node-fhtml', 'node-firestore', 'node-firestore-rules', 'node-railway-api', 'node-firebase-auth', 'node-openai', 'node-cloud-functions'];
for (const c of liveComp) { const st = (snap.components[c] || {}).status || 'UNKNOWN'; console.log(`   ${mark(st)} ${c.replace('node-', '').padEnd(24)} ${st}${(snap.components[c] || {}).errorCode ? ' (' + snap.components[c].errorCode + ')' : ''}`); }

console.log('\n  RELEASE-CRITICAL JOURNEYS:');
for (const j of policy.releaseCriticalJourneys) { const st = (snap.journeys[j] || {}).status || 'UNKNOWN'; console.log(`   ${mark(st)} ${j.padEnd(24)} ${st}`); }

const blocking = rr.blocking, warnings = rr.warnings;
console.log(`\n  BLOCKING (${blocking.length}):`);
if (!blocking.length) console.log('   none');
for (const b of blocking.sort((a, z) => (a.severity > z.severity ? 1 : -1))) {
  console.log(`   ${b.severity} · BLOCKING  ${b.id}  [${(b.platforms || []).join('/')}]`);
  console.log(`       ${b.title}`);
  if (b.resolution) console.log(`       resolve: ${b.resolution}`);
}
console.log(`\n  WARNINGS (${warnings.length}):`);
if (!warnings.length) console.log('   none');
for (const b of warnings) console.log(`   ${b.severity} · WARNING   ${b.id} — ${b.title}`);

const pl = rr.platforms;
console.log('\n  PLATFORM READINESS (blocking items only):');
console.log(`   iOS:      ${pl.ios.verdict}   (blocking=${pl.ios.blocking}: P0=${pl.ios.p0} P1=${pl.ios.p1})`);
console.log(`   ANDROID:  ${pl.android.verdict}   (blocking=${pl.android.blocking}: P0=${pl.android.p0} P1=${pl.android.p1})`);
console.log('\n  VERDICT: ' + rr.verdict + '   (exit ' + rr.exitCode + ')\n');
process.exit(rr.exitCode);
