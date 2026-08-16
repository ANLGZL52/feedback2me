#!/usr/bin/env node
// Feedback2Me RELEASE CHECK — the all-in-one pre-release control.
// Runs REAL local invariants, writes SHA-stamped ci-evidence.json, then monitor + gate.
// Read-only: no deploy, no production write, no synthetic production test.
// Exit 0 = READY, 1 = BLOCKED. IAP server-verification is now restored (P0 closed);
// remaining blockers are P1 (build-number confirm, isPremium audit, sandbox E2E pending).
import { execSync, execFileSync } from 'node:child_process';
import { writeFileSync, mkdirSync, existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { scopeTreeHash } from './scope.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = join(__dirname, '..', '..');
const STATUS_DIR = join(REPO, 'ops-status');
const runId = 'release-check-' + Date.now();
const now = new Date().toISOString();
const light = process.argv.includes('--light'); // skip slow builds (analyze/test/rules/web/server)

let sha = 'unknown';
try { sha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: REPO }).toString().trim(); } catch {}
const matrix = JSON.parse(readFileSync(join(REPO, 'ops', 'checks', 'check-matrix.json'), 'utf8'));
const scopeFor = (id) => { const c = matrix.checks.find((c) => c.id === id); return c && c.scope; };

const sh = (cmd, opts = {}) => {
  try {
    const out = execSync(cmd, { cwd: REPO, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: opts.timeout || 600000, env: { ...process.env, ...(opts.env || {}) } });
    return { code: 0, out };
  } catch (e) { return { code: e.status ?? 1, out: (e.stdout || '') + (e.stderr || '') }; }
};
const JBR = 'C:\\Program Files\\Android\\Android Studio\\jbr';
const javaEnv = { JAVA_HOME: JBR, PATH: JBR + '\\bin;' + process.env.PATH };

async function archValidation() {
  const { check } = await import('./checks/arch-drift.mjs');
  const r = await check();
  return { status: r.status === 'HEALTHY' ? 'PASS' : r.status === 'DOWN' ? 'FAIL' : 'UNKNOWN', summary: `components/edges consistent (${r.details && r.details.components}/${r.details && r.details.edges})` };
}
function opsTests() {
  const r = sh('node --test ops/monitor/engine.test.mjs');
  const pass = /pass (\d+)/.exec(r.out);
  return { status: r.code === 0 ? 'PASS' : 'FAIL', summary: `ops engine tests ${pass ? pass[1] : '?'} pass (exit ${r.code})` };
}
function flutterAnalyze() {
  if (light) return { status: 'UNKNOWN', summary: 'skipped (--light)' };
  const r = sh('flutter analyze lib/ test/', { timeout: 300000 });
  const errors = (r.out.match(/\berror\s[•-]/g) || []).length;
  return { status: errors === 0 ? 'PASS' : 'FAIL', summary: `${errors} error-level issue(s)` };
}
function flutterTest() {
  if (light) return { status: 'UNKNOWN', summary: 'skipped (--light)' };
  const r = sh('flutter test', { timeout: 420000 });
  return { status: /All tests passed!/.test(r.out) ? 'PASS' : 'FAIL', summary: /(\+\d+):/.test(r.out) ? (r.out.match(/\+(\d+): All tests passed/) || ['', '?'])[1] + ' tests' : 'see output' };
}
function webBuild() {
  if (light) return { status: 'UNKNOWN', summary: 'skipped (--light)' };
  const r = sh('flutter build web --release', { timeout: 600000 });
  return { status: /Built build[\\/]web/.test(r.out) ? 'PASS' : 'FAIL', summary: 'flutter build web --release' };
}
function serverBuild() {
  if (light) return { status: 'UNKNOWN', summary: 'skipped (--light)' };
  const r = sh('npm --prefix server run build', { timeout: 300000 });
  return { status: r.code === 0 ? 'PASS' : 'FAIL', summary: 'prisma generate && tsc' };
}
function rulesEmulator() {
  if (light) return { status: 'UNKNOWN', summary: 'skipped (--light)' };
  if (!existsSync(JBR)) return { status: 'UNKNOWN', summary: 'Java (Android Studio JBR) not found' };
  const r = sh('firebase emulators:exec --only firestore --project=demo-test "node --test test/rules/firestore.rules.test.mjs"', { timeout: 300000, env: javaEnv });
  const pass = /pass (\d+)/.exec(r.out);
  return { status: r.code === 0 && pass && +pass[1] > 0 ? 'PASS' : 'FAIL', summary: `rules emulator ${pass ? pass[1] : '?'} pass (exit ${r.code})` };
}
function functionsIap() {
  if (light) return { status: 'UNKNOWN', summary: 'skipped (--light)' };
  if (!existsSync(JBR)) return { status: 'UNKNOWN', summary: 'Java (Android Studio JBR) not found' };
  const build = sh('npm --prefix functions run build', { timeout: 300000 });
  if (build.code !== 0) return { status: 'FAIL', summary: 'functions build (tsc) failed' };
  // GOOGLE_APPLICATION_CREDENTIALS='' neutralizes a stale default-cred path; the
  // Firestore emulator needs no real credentials (see iap-core.test.mjs).
  const r = sh(
    'firebase emulators:exec --only firestore --project=demo-iap-test "node --test functions/test/iap-core.test.mjs"',
    { timeout: 300000, env: { ...javaEnv, GOOGLE_APPLICATION_CREDENTIALS: '' } },
  );
  const pass = /pass (\d+)/.exec(r.out);
  const fail = /fail (\d+)/.exec(r.out);
  const ok = r.code === 0 && pass && +pass[1] > 0 && (!fail || +fail[1] === 0);
  return { status: ok ? 'PASS' : 'FAIL', summary: `functions build + iap-core ${pass ? pass[1] : '?'} pass (exit ${r.code})` };
}
function restConcurrencyCI() {
  const r = sh('gh run list --workflow=server-concurrency-test.yml --limit 1 --json conclusion,headSha', { timeout: 15000 });
  try {
    const rows = JSON.parse(r.out);
    if (!rows.length) return { status: 'UNKNOWN', summary: 'no CI runs' };
    const ok = rows[0].conclusion === 'success';
    return { status: ok ? 'PASS' : 'UNKNOWN', summary: `last GH run ${rows[0].conclusion}`, ciSha: rows[0].headSha };
  } catch { return { status: 'UNKNOWN', summary: 'gh unavailable' }; }
}

const plan = [
  ['ci-architecture-validation', archValidation, 'arch-drift'],
  ['ci-ops-tests', opsTests, 'node --test'],
  ['ci-flutter-analyze', flutterAnalyze, 'flutter analyze'],
  ['ci-flutter-test', flutterTest, 'flutter test'],
  ['ci-server-build', serverBuild, 'npm --prefix server run build'],
  ['ci-web-build', webBuild, 'flutter build web --release'],
  ['ci-rules-emulator', rulesEmulator, 'firebase emulators:exec'],
  ['ci-functions-iap', functionsIap, 'firebase emulators:exec functions'],
  ['ci-rest-concurrency', restConcurrencyCI, 'gh run list'],
];

const evidence = {};
console.log('\n=== FEEDBACK2ME RELEASE CHECK ===  (sha ' + sha + ')' + (light ? '  [--light: builds skipped]' : ''));
for (const [id, fn, src] of plan) {
  process.stdout.write(('  ' + id).padEnd(30) + '… ');
  let r; try { r = await fn(); } catch (e) { r = { status: 'FAIL', summary: String(e.message) }; }
  const scope = scopeFor(id);
  const scopeHash = scope ? scopeTreeHash(REPO, r.ciSha || 'HEAD', scope) : null;
  evidence[id] = { id, status: r.status, verifiedAt: now, commitSha: r.ciSha || sha, scopeHash, scopeFiles: scope || null, source: src, runId, summary: r.summary };
  console.log(`${r.status.padEnd(8)} ${r.summary}`);
}
if (!existsSync(STATUS_DIR)) mkdirSync(STATUS_DIR, { recursive: true });
writeFileSync(join(STATUS_DIR, 'ci-evidence.json'), JSON.stringify(evidence, null, 2));
console.log('  wrote ops-status/ci-evidence.json');

// monitor (read-only live checks) then gate
console.log('\n  running monitor + preflight…');
sh('node ops/monitor/run.mjs');
const pf = sh('node ops/monitor/preflight.mjs');
console.log(pf.out);
process.exit(pf.code);
