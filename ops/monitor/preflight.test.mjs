// Preflight exit-code semantics — separates OBSERVABILITY execution health from
// RELEASE readiness. Run: node --test ops/monitor/preflight.test.mjs
//   exit 0 = READY, 1 = NOT READY (valid verdict), 2 = EXECUTION ERROR.
// A NOT READY verdict must NOT read as a failure of the monitoring system; only a
// real execution error (missing/malformed snapshot, crash) exits 2.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PREFLIGHT = join(__dirname, 'preflight.mjs');
const TMP = join(__dirname, '..', '..', 'ops-status', '.preflight-test');

const run = (snapPath) => spawnSync(process.execPath, [PREFLIGHT, snapPath], { encoding: 'utf8' }).status;
const writeSnap = (name, obj) => { const p = join(TMP, name); writeFileSync(p, typeof obj === 'string' ? obj : JSON.stringify(obj)); return p; };

// A snapshot the release gate must judge NOT READY (has a release-blocking item).
const NOT_READY = {
  generatedAt: '2026-01-01T00:00:00Z', environment: 'production', release: 'test', build: 1,
  components: { 'node-firestore': { status: 'HEALTHY' } }, journeys: {}, incidents: [], ciEvidence: {},
  blockers: [{ id: 'build-number-unconfirmed', severity: 'P1', releaseBlocking: true, platforms: ['ios', 'android'] }],
};

before(() => { mkdirSync(TMP, { recursive: true }); });
after(() => { try { rmSync(TMP, { recursive: true, force: true }); } catch {} });

test('CASE 1: monitor healthy + release NOT READY → exit 1 (NOT a monitoring failure)', () => {
  assert.equal(run(writeSnap('not-ready.json', NOT_READY)), 1);
});

test('CASE 2: a valid snapshot yields a readiness verdict in {0,1}, never an error code', () => {
  const code = run(writeSnap('valid.json', NOT_READY));
  assert.ok(code === 0 || code === 1, `expected readiness verdict 0/1, got ${code}`);
  assert.notEqual(code, 2); // a valid snapshot must never look like an execution error
});

test('CASE 4a: missing snapshot → exit 2 (EXECUTION ERROR, surfaced as workflow failure)', () => {
  assert.equal(run(join(TMP, 'does-not-exist.json')), 2);
});

test('CASE 4b: malformed snapshot JSON → exit 2 (EXECUTION ERROR)', () => {
  assert.equal(run(writeSnap('broken.json', '{ not valid json ')), 2);
});

test('exit codes are the three distinct values only (0/1/2)', () => {
  const codes = new Set([run(writeSnap('a.json', NOT_READY)), run(join(TMP, 'missing.json'))]);
  for (const c of codes) assert.ok([0, 1, 2].includes(c));
});
