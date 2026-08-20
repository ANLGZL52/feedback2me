// Feedback2Me — END-TO-END HEALTH ENGINE. Pure functions. Turns the existing ops-status
// artifacts (+ optional on-demand canary results) into evidence-based per-node health,
// product critical-path health, business (money-safety) health, coverage, and a single
// overallSystemHealth with failure propagation. NEVER fabricates: N/A stays N/A, IDLE ≠
// unhealthy, UNKNOWN ≠ healthy, and DEFERRED validation never marks runtime unhealthy.
import { NODES } from '../topology/nodes.js';
import { NODE_HEALTH, CRITICAL_PATHS, CANARIES } from '../topology/health-map.js';
import { normalizeStatus } from './topology-model.mjs';

const MONEY_CODES = new Set(['IAP_MONEY_SAFETY_BREACH', 'IAP_GRANT_DELTA_NOT_ONE', 'IAP_REPLAY_DELTA_NOT_ZERO', 'IAP_CREDIT_UNKNOWN_PRODUCT', 'IAP_INVALID_PRODUCT_CREDITED', 'IAP_CREDIT_AFTER_FAILURE', 'IAP_DUPLICATE_GRANT', 'IAP_SUCCESS_WITHOUT_CREDIT']);
const RANK = { UNHEALTHY: 5, DEGRADED: 4, UNKNOWN: 3, IDLE: 1, HEALTHY: 0 };
const isFailing = (s) => ['UNHEALTHY', 'CRITICAL', 'BLOCK', 'DOWN', 'FAILED', 'UNAVAILABLE'].includes(s);
const isDegraded = (s) => ['DEGRADED', 'WARN', 'PARTIAL'].includes(s);
const isOk = (s) => ['HEALTHY', 'FULL', 'LIVE', 'VERIFIED', 'PASS', 'OK'].includes(s);
const isIdle = (s) => s === 'IDLE';
const isUnknown = (s) => ['UNKNOWN', 'NOT_CONFIGURED'].includes(s);

const comp = (art, id) => { const c = art.latest && art.latest.components && art.latest.components[id]; return c ? (c.status || 'UNKNOWN') : 'UNKNOWN'; };
const dom = (art, k) => { const d = art.health && art.health.domains && art.health.domains[k]; return d ? (d.status || 'UNKNOWN') : 'UNKNOWN'; };

// ---- money-safety business health ----
export function moneySafety(art) {
  const incidents = (art.incidentState && art.incidentState.incidents) || [];
  const violations = incidents.filter((i) => i.state === 'OPEN' && MONEY_CODES.has(i.code)).map((i) => i.code);
  // also honor an explicit UNHEALTHY IAP domain flagged by a money-safety alert if present
  const status = violations.length ? 'UNHEALTHY' : 'HEALTHY';
  return { status, violations, realIapE2E: (art.health && art.health.validationEvidence && art.health.validationEvidence.realIapE2E) || 'DEFERRED' };
}

// ---- resolve one signal source to a status string ----
function resolveService(src, art, canaries) {
  if (!src) return 'UNKNOWN';
  switch (src.kind) {
    case 'na': return 'N/A';
    case 'const': return src.value;
    case 'field': return (art.health && art.health[src.key]) || 'UNKNOWN';
    case 'domain': return dom(art, src.key);
    case 'component': return comp(art, src.id);
    case 'business': return moneySafety(art).status;
    case 'gate': return (art.health && art.health.productReleaseGate && art.health.productReleaseGate.status) || 'UNKNOWN';
    case 'incident': return (art.incidentActions && art.incidentActions.mode) || 'UNKNOWN';
    case 'digest': return (art.digestDelivery && art.digestDelivery.health) || 'UNKNOWN';
    case 'digestChannel': { const d = art.digestDelivery; if (!d) return 'UNKNOWN'; if (d.health === 'NOT_CONFIGURED') return 'NOT_CONFIGURED'; return d.channel === 'slack' ? 'LIVE' : 'UNKNOWN'; }
    case 'deferred': return 'DEFERRED';
    case 'canary': return (canaries && canaries[src.id] && canaries[src.id].status) || 'UNKNOWN';
    default: return 'UNKNOWN';
  }
}
const trafficLabel = (s) => (isIdle(s) ? 'IDLE (no traffic)' : isOk(s) ? 'ACTIVE' : isDegraded(s) ? 'ELEVATED' : isFailing(s) ? 'FAILING' : 'UNKNOWN');

const PATH_OF = (() => { const m = {}; for (const p of CRITICAL_PATHS) for (const n of p.members) (m[n] = m[n] || []).push(p.id); return m; })();

// ---- resolve one node's end-to-end health ----
export function resolveNode(id, art, canaries = {}) {
  const e = NODE_HEALTH[id] || { service: { kind: 'na' }, probe: false };
  let serviceHealth = resolveService(e.service, art, canaries);
  // a run canary can UPGRADE an UNKNOWN/N-A availability into real evidence (never downgrades a real signal silently)
  let canaryStatus = null;
  if (e.canary && canaries[e.canary]) { canaryStatus = canaries[e.canary].status; if (isUnknown(serviceHealth) || serviceHealth === 'N/A') serviceHealth = canaryStatus; }
  const trafficState = e.traffic ? trafficLabel(dom(art, e.traffic)) : null;
  const business = e.business ? moneySafety(art).status : (e.service && e.service.kind === 'business' ? moneySafety(art).status : null);
  const { severity } = normalizeStatus(serviceHealth);
  const naReason = (serviceHealth === 'N/A' || isUnknown(serviceHealth)) ? (e.naReason || null) : null;
  return {
    id, serviceHealth, severity, trafficState, business,
    probe: !!e.probe, observable: serviceHealth !== 'N/A',
    e2e: !!PATH_OF[id], paths: PATH_OF[id] || [],
    source: e.service ? e.service.kind : 'na', canary: e.canary || null, canaryStatus,
    naReason, recommend: (serviceHealth === 'N/A' || isUnknown(serviceHealth)) ? (e.recommend || null) : null,
    separate: e.separate || null,
  };
}

// ---- product critical paths ----
export function criticalPaths(art, canaries = {}) {
  const ms = moneySafety(art);
  return CRITICAL_PATHS.map((p) => {
    const resolved = p.members.map((id) => ({ id, r: resolveNode(id, art, canaries) }));
    const signals = resolved.filter((m) => m.r.serviceHealth !== 'N/A');
    const gaps = resolved.filter((m) => m.r.serviceHealth === 'N/A').map((m) => m.id);
    let status, weakest = null;
    const failing = signals.find((m) => isFailing(m.r.serviceHealth));
    const degraded = signals.find((m) => isDegraded(m.r.serviceHealth) && m.id !== 'release_gate');
    const unknowns = signals.filter((m) => isUnknown(m.r.serviceHealth));
    const oks = signals.filter((m) => isOk(m.r.serviceHealth) || isIdle(m.r.serviceHealth));
    if (p.id === 'IAP' && ms.status === 'UNHEALTHY') { status = 'UNHEALTHY'; weakest = 'iap_verify'; }
    else if (failing) { status = 'UNHEALTHY'; weakest = failing.id; }
    else if (degraded) { status = 'DEGRADED'; weakest = degraded.id; }
    else if (!signals.length) { status = 'UNKNOWN'; }
    else if (unknowns.length && oks.length) { status = 'PARTIAL'; weakest = unknowns[0].id; }
    else if (unknowns.length === signals.length) { status = 'UNKNOWN'; weakest = unknowns[0] && unknowns[0].id; }
    else status = 'HEALTHY'; // all observable signals OK/IDLE; N/A members are a coverage gap (see `gaps`), not a downgrade
    return { id: p.id, name: p.name, status, weakest, gaps, members: resolved.map((m) => ({ id: m.id, status: m.r.serviceHealth })) };
  });
}

// ---- coverage ----
export function coverage(art, canaries = {}) {
  const resolved = NODES.map((n) => resolveNode(n.id, art, canaries));
  const total = resolved.length;
  const observable = resolved.filter((r) => r.observable).length;
  const probed = resolved.filter((r) => r.probe).length;
  const paths = criticalPaths(art, canaries);
  const covered = paths.filter((p) => p.status !== 'UNKNOWN').length;
  return { total, observable, probed, criticalPaths: { covered, total: paths.length } };
}

// ---- incident lookup for propagation ----
function incidentFor(art, nodeId) {
  const n = NODES.find((x) => x.id === nodeId); if (!n) return null;
  const incidents = (art.incidentState && art.incidentState.incidents) || [];
  const codes = new Set(n.alertCodes || []);
  const hit = incidents.find((i) => i.state === 'OPEN' && (codes.has(i.code) || i.domain === domainOf(nodeId)));
  return hit ? { code: hit.code, issueNumber: hit.issueNumber ?? null } : null;
}
function domainOf(id) { const e = NODE_HEALTH[id]; if (e && e.service && e.service.kind === 'domain') return e.service.key; if (e && e.traffic) return e.traffic; return null; }

// ---- overall system health (critical-path & money-safety dominant) ----
export function overallSystemHealth(art, canaries = {}) {
  const reasons = [];
  const ms = moneySafety(art);
  const paths = criticalPaths(art, canaries);
  const pathsByNode = (id) => paths.filter((p) => p.weakest === id || (CRITICAL_PATHS.find((c) => c.id === p.id).members.includes(id))).map((p) => p.name);
  const addReason = (node, status, alert) => reasons.push({ node, label: (NODES.find((n) => n.id === node) || {}).label || node, status, paths: pathsByNode(node), alert: alert || null, incident: incidentFor(art, node) });

  let status = 'HEALTHY';
  const set = (s) => { if (RANK[s] > RANK[status] || (s === 'UNKNOWN' && status === 'HEALTHY')) status = s; };

  // money-safety dominates
  if (ms.status === 'UNHEALTHY') { status = 'UNHEALTHY'; addReason('iap_verify', 'UNHEALTHY', ms.violations[0] || 'IAP_MONEY_SAFETY_BREACH'); }
  // postgres critical dominates
  const pg = resolveNode('postgres', art, canaries).serviceHealth;
  if (isFailing(pg)) { status = 'UNHEALTHY'; addReason('postgres', 'UNHEALTHY', 'POSTGRES_CRITICAL'); }
  // any critical path failing/degraded
  for (const p of paths) {
    if (p.status === 'UNHEALTHY') { status = 'UNHEALTHY'; if (p.weakest && !reasons.find((r) => r.node === p.weakest)) addReason(p.weakest, 'UNHEALTHY'); }
    else if (p.status === 'DEGRADED') { set('DEGRADED'); if (p.weakest && !reasons.find((r) => r.node === p.weakest)) addReason(p.weakest, 'DEGRADED'); }
  }
  // collector blindness = observability degraded (policy), not runtime unhealthy
  const collector = resolveNode('collector', art, canaries).serviceHealth;
  if (isUnknown(collector)) { set('DEGRADED'); if (!reasons.find((r) => r.node === 'collector')) addReason('collector', 'DEGRADED', 'COLLECTOR_STALE'); }
  // runtime health field
  const rt = (art.health && art.health.currentRuntimeHealth) || 'UNKNOWN';
  if (isFailing(rt)) status = 'UNHEALTHY'; else if (isDegraded(rt)) set('DEGRADED'); else if (isUnknown(rt) && status === 'HEALTHY') status = 'UNKNOWN';

  return {
    status,
    reasons,
    moneySafety: ms.status,
    realIapE2E: ms.realIapE2E, // stays DEFERRED, never affects `status`
    runtimeValidation: (art.health && art.health.runtimeValidationStatus) || 'UNKNOWN',
    releaseGate: (art.health && art.health.productReleaseGate && art.health.productReleaseGate.status) || 'UNKNOWN', // separate from runtime
    paths,
  };
}

// full assembled system payload for /api/system
export function buildSystem(art, canaries = {}) {
  const overall = overallSystemHealth(art, canaries);
  return {
    overall: overall.status,
    reasons: overall.reasons,
    moneySafety: overall.moneySafety,
    realIapE2E: overall.realIapE2E,
    runtimeValidation: overall.runtimeValidation,
    releaseGate: overall.releaseGate,
    paths: overall.paths,
    coverage: coverage(art, canaries),
    canaryRunAt: canaries.__runAt || null,
    canaries: Object.entries(canaries).filter(([k]) => !k.startsWith('__')).map(([id, v]) => ({ id, status: v.status, detail: v.detail, node: v.node, desc: v.desc })),
  };
}

export { CANARIES, NODE_HEALTH, CRITICAL_PATHS };
