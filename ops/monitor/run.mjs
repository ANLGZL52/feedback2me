#!/usr/bin/env node
// Feedback2Me Ops monitor runner. Runs PRODUCTION-SAFE READ-ONLY checks, applies
// the health engine, and writes ops-status/latest.json + an events JSONL log.
// NEVER writes to production. NEVER logs PII/secrets (operational metadata only).
import { readFileSync, writeFileSync, existsSync, mkdirSync, appendFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { applyCheckResult, reconcileIncidents, buildSnapshot } from './engine.mjs';
import { scopeTreeHash } from './scope.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = join(__dirname, '..', '..');
const ARCH = join(REPO, 'docs', 'architecture');
const OPS = join(REPO, 'ops');
const STATUS_DIR = join(REPO, 'ops-status');

const load = (p) => JSON.parse(readFileSync(p, 'utf8'));
const inv = load(join(ARCH, 'component-inventory.json'));
const graph = load(join(ARCH, 'dependency-graph.json'));
const matrix = load(join(OPS, 'checks', 'check-matrix.json'));
const policy = load(join(OPS, 'checks', 'health-policy.json'));

const nowIso = new Date().toISOString();
const runId = 'run-' + Date.now();
const sim = process.argv.includes('--sim');
const environment = sim ? 'simulation' : 'production';

let release = null, build = null;
try { release = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: REPO }).toString().trim(); } catch {}
try { build = (readFileSync(join(REPO, 'pubspec.yaml'), 'utf8').match(/^version:\s*[\d.]+\+(\d+)/m) || [])[1] || null; } catch {}

// prev state
let prev = {};
const latestPath = join(STATUS_DIR, 'latest.json');
if (existsSync(latestPath)) { try { prev = load(latestPath); } catch {} }
const prevComp = prev.components || {};

// init every component UNKNOWN
const componentStates = {};
for (const c of inv.components) componentStates[c.id] = prevComp[c.id] || { status: 'UNKNOWN' };

const events = [];
let minSupportedBuild = prev.minSupportedBuild ?? null;
const ciEvidence = {};
// Service-health signals (reachability of a service) kept SEPARATE from the
// journey-critical component status, so a reachable service never fakes a
// verified user journey (e.g. Firebase Auth reachable != owner sign-in verified).
const serviceHealth = {};

for (const chk of matrix.checks) {
  if (sim) continue; // simulation mode: skip live network, dashboard uses fixture
  const impl = chk.implementation;
  const th = { ...policy.thresholds, failureThreshold: chk.failureThreshold, recoveryThreshold: chk.recoveryThreshold };

  if (chk.type === 'ci-invariant') {
    // CI evidence is filled by CI (ops-status/ci-evidence.json); else UNKNOWN (LAST VERIFIED, not live)
    if (impl === 'arch-drift.mjs') {
      try {
        const { check } = await import('./checks/arch-drift.mjs');
        const r = await check(chk);
        ciEvidence[chk.id] = { status: r.status === 'HEALTHY' ? 'PASS' : r.status === 'DOWN' ? 'FAIL' : 'UNKNOWN', verifiedAt: nowIso, detail: r.errorCode, commitSha: release, scopeHash: chk.scope ? scopeTreeHash(REPO, 'HEAD', chk.scope) : null };
      } catch { ciEvidence[chk.id] = { status: 'UNKNOWN', verifiedAt: null, detail: 'runner-error' }; }
    } else {
      ciEvidence[chk.id] = readCiEvidence(chk.id);
    }
    continue;
  }

  if (!impl || impl === 'none') {
    events.push(ev(chk, 'UNKNOWN', { errorCode: 'NO_SAFE_LIVE_CHECK' }));
    continue; // component stays UNKNOWN (honest)
  }

  let r;
  try {
    const { check } = await import('./checks/' + impl);
    r = await check(chk);
  } catch (e) {
    r = { status: 'UNKNOWN', errorCode: 'ADAPTER_ERROR', details: { error: String(e.message) } };
  }
  if (r.details && typeof r.details.minSupportedBuild === 'number') minSupportedBuild = r.details.minSupportedBuild;

  if (chk.serviceHealthOnly) {
    // Record reachability without touching the journey-critical component status.
    serviceHealth[chk.componentId] = { status: r.status, checkId: chk.id, latencyMs: r.latencyMs ?? null, errorCode: r.errorCode ?? null, note: (r.details && r.details.note) || null, ts: nowIso };
    events.push(ev(chk, r.status, r));
    continue;
  }

  componentStates[chk.componentId] = applyCheckResult(componentStates[chk.componentId], { status: r.status, ts: nowIso, latencyMs: r.latencyMs, errorCode: r.errorCode, severity: chk.criticality === 'critical' ? null : null }, th);
  componentStates[chk.componentId].checkId = chk.id;
  events.push(ev(chk, componentStates[chk.componentId].status, r));
}

// current scope fingerprints for scoped CI-evidence freshness
const currentScopeHashes = {};
for (const inv of (policy.releaseGate.requiredCiInvariants || [])) {
  const chk = matrix.checks.find((c) => c.id === inv);
  if (chk && chk.scope) currentScopeHashes[inv] = scopeTreeHash(REPO, 'HEAD', chk.scope);
}

const incidents = reconcileIncidents(prev.incidents || [], componentStates, policy, { ts: nowIso, runId, release, build });
const snapshot = buildSnapshot({ componentStates, edges: graph.edges, policy, incidents, ciEvidence, meta: { ts: nowIso, runId, environment, release, build, minSupportedBuild, currentScopeHashes } });
snapshot.serviceHealth = serviceHealth; // service reachability, separate from journey status

if (!existsSync(STATUS_DIR)) mkdirSync(STATUS_DIR, { recursive: true });
writeFileSync(latestPath, JSON.stringify(snapshot, null, 2));
// events JSONL -> ops-status/events/ (gitignored; CI uploads as artifact, NOT committed every run)
const evDir = join(STATUS_DIR, 'events'); if (!existsSync(evDir)) mkdirSync(evDir, { recursive: true });
const evFile = join(evDir, nowIso.slice(0, 10) + '.jsonl');
for (const e of events) appendFileSync(evFile, JSON.stringify(e) + '\n');

// summary
const jl = Object.entries(snapshot.journeys).map(([k, v]) => `${k}=${v.status}`).join('  ');
console.log(`[ops] ${environment} ${nowIso}  overall=${snapshot.overall}  build=${build} minSupported=${minSupportedBuild}`);
console.log('[ops] journeys: ' + jl);
console.log('[ops] blockers: ' + (snapshot.blockers.length ? snapshot.blockers.map((b) => b.severity + ':' + b.id).join(', ') : 'none'));
console.log('[ops] wrote ' + latestPath);

function ev(chk, status, r) {
  return {
    timestamp: nowIso, environment, runId, checkId: chk.id, componentId: chk.componentId || null,
    edgeId: null, journeyId: (chk.journeys && chk.journeys[0]) || null, status,
    severity: null, latencyMs: r.latencyMs ?? null, httpStatus: r.httpStatus ?? null,
    errorCode: r.errorCode ?? null, releaseSha: release, appBuild: build, dependency: null,
    correlationId: runId, message: chk.componentId + ' ' + status, details: safeDetails(r.details),
  };
}
// strip anything that could be PII/secret; only allow known operational keys
function safeDetails(d) {
  const allow = ['minSupportedBuild', 'latestBuild', 'headSha', 'createdAt', 'note', 'components', 'edges', 'problems'];
  const out = {}; if (d) for (const k of allow) if (k in d) out[k] = d[k]; return out;
}
function readCiEvidence(id) {
  const p = join(STATUS_DIR, 'ci-evidence.json');
  if (existsSync(p)) { try { const e = load(p); if (e[id]) return e[id]; } catch {} }
  return { status: 'UNKNOWN', verifiedAt: null, detail: 'no CI evidence recorded' };
}
