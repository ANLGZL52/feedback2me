// Feedback2Me Ops — pure health engine (no I/O, fully testable).
// Turns raw check results + architecture graph + health policy into
// component/edge/journey health, overall status, and incidents.
// NO FAKE HEALTH: absence of a real check => UNKNOWN.

import { evidenceFresh } from './scope.mjs';

export const STATUS = ['HEALTHY', 'UNKNOWN', 'CHECKING', 'DEGRADED', 'DOWN'];
const RANK = { HEALTHY: 0, UNKNOWN: 1, CHECKING: 1, DEGRADED: 2, DOWN: 3 };

export function worse(a, b) {
  return (RANK[b] ?? 1) > (RANK[a] ?? 1) ? b : a;
}
export function statusOf(map, id) {
  return (map && map[id]) || 'UNKNOWN';
}

// ---- Edge health: derived from endpoints unless a direct edge check exists ----
export function edgeStatus(sFrom, sTo) {
  if (sFrom === 'DOWN' || sTo === 'DOWN') return 'DOWN';
  if (sFrom === 'DEGRADED' || sTo === 'DEGRADED') return 'DEGRADED';
  if (sFrom === 'UNKNOWN' || sTo === 'UNKNOWN' || sFrom === 'CHECKING' || sTo === 'CHECKING') return 'UNKNOWN';
  return 'HEALTHY';
}
export function computeEdges(componentStatus, edges, directEdgeStatus = {}) {
  const out = {};
  for (const e of edges) {
    if (directEdgeStatus[e.id]) { out[e.id] = directEdgeStatus[e.id]; continue; }
    out[e.id] = edgeStatus(statusOf(componentStatus, e.from), statusOf(componentStatus, e.to));
  }
  return out;
}

// ---- Journey health: path-based, fallback/XOR aware ----
export function journeyStatus(componentStatus, jpol, policy = {}) {
  const hard = jpol.hardDeps || [];
  const soft = jpol.softDeps || [];
  const groups = jpol.fallbackGroups || [];
  const affectedBy = [];
  let fallbackUsed = false;
  let anyDown = false, anyDegraded = false, anyUnknown = false;

  const coveredByFallback = (id) => {
    const g = groups.find((g) => g.primary === id);
    return !!g && (g.alternates || []).some((a) => statusOf(componentStatus, a) === 'HEALTHY');
  };

  for (const id of hard) {
    const s = statusOf(componentStatus, id);
    if (s === 'DOWN') {
      if (coveredByFallback(id)) { anyDegraded = true; fallbackUsed = true; affectedBy.push(id + ' (fallback active)'); }
      else { anyDown = true; affectedBy.push(id); }
    } else if (s === 'DEGRADED') { anyDegraded = true; affectedBy.push(id); }
    else if (s === 'UNKNOWN' || s === 'CHECKING') { anyUnknown = true; }
  }
  for (const id of soft) {
    const s = statusOf(componentStatus, id);
    if (s === 'DOWN' || s === 'DEGRADED') { anyDegraded = true; affectedBy.push(id + ' (soft)'); }
  }

  let status = anyDown ? 'DOWN' : anyDegraded ? 'DEGRADED' : anyUnknown ? 'UNKNOWN' : 'HEALTHY';

  // static architecture risk (e.g. IAP gap) caps the best achievable status
  const risks = policy.staticRisks || [];
  if (jpol.staticRisk) {
    const r = risks.find((x) => x.id === jpol.staticRisk);
    if (r && r.capsJourneyAt) status = worse(status, r.capsJourneyAt);
  }
  return { status, fallbackUsed, affectedBy, staticRisk: jpol.staticRisk || null };
}

export function computeJourneys(componentStatus, policy) {
  const out = {};
  for (const [jid, jpol] of Object.entries(policy.journeys || {})) {
    out[jid] = journeyStatus(componentStatus, jpol, policy);
  }
  return out;
}

export function computeOverall(journeyResults, criticalJourneys) {
  let down = false, degraded = false, healthy = false, unknown = false;
  for (const j of criticalJourneys) {
    const s = (journeyResults[j] && journeyResults[j].status) || 'UNKNOWN';
    if (s === 'DOWN') down = true;
    else if (s === 'DEGRADED') degraded = true;
    else if (s === 'HEALTHY') healthy = true;
    else unknown = true;
  }
  if (down) return 'CRITICAL';
  if (degraded) return 'DEGRADED';
  if (healthy && !unknown) return 'HEALTHY';
  return 'UNKNOWN';
}

// ---- Failure propagation: which journeys does a component affect ----
export function affectedJourneys(componentId, policy) {
  const hit = [];
  for (const [jid, jpol] of Object.entries(policy.journeys || {})) {
    const all = [...(jpol.hardDeps || []), ...(jpol.softDeps || [])];
    if (all.includes(componentId)) hit.push(jid);
  }
  return hit;
}

// ---- Incident threshold state machine (per component) ----
// prev: { status, consecutiveFail, consecutiveOk, lastGood, lastFailure }
// raw:  { status:'HEALTHY'|'DOWN'|'UNKNOWN', ts, latencyMs, errorCode, severity }
export function applyCheckResult(prev, raw, thresholds) {
  const t = thresholds || {};
  const degradeOn = t.degradeOnFailures ?? 1;
  const downOn = t.downOnConsecutiveFailures ?? 2;
  const recoverOn = t.recoverOnConsecutiveSuccesses ?? 2;
  const p = prev || { status: 'UNKNOWN', consecutiveFail: 0, consecutiveOk: 0, lastGood: null, lastFailure: null };
  const next = { ...p, latencyMs: raw.latencyMs ?? null, errorCode: raw.errorCode ?? null, lastCheck: raw.ts };

  if (raw.status === 'UNKNOWN' || raw.status === 'CHECKING') {
    next.status = raw.status; // do not fabricate health; keep counters
    return next;
  }
  if (raw.status === 'DEGRADED') {
    next.status = 'DEGRADED'; next.consecutiveOk = 0; next.errorCode = raw.errorCode ?? null; next.lastFailure = raw.ts;
    return next;
  }
  if (raw.status === 'DOWN') {
    next.consecutiveFail = (p.consecutiveFail || 0) + 1;
    next.consecutiveOk = 0;
    next.lastFailure = raw.ts;
    if ((raw.severity === 'P0' && t.p0InvariantImmediateDown) || next.consecutiveFail >= downOn) next.status = 'DOWN';
    else if (next.consecutiveFail >= degradeOn) next.status = 'DEGRADED';
    else next.status = p.status === 'HEALTHY' ? 'HEALTHY' : 'DEGRADED';
    return next;
  }
  // HEALTHY raw. Recovery gating applies only when recovering from a real bad
  // state (DEGRADED/DOWN); from UNKNOWN/CHECKING a success is HEALTHY immediately
  // (UNKNOWN is "not observed", not a failure to recover from).
  next.consecutiveOk = (p.consecutiveOk || 0) + 1;
  next.consecutiveFail = 0;
  next.lastGood = raw.ts;
  const recovering = p.status === 'DEGRADED' || p.status === 'DOWN';
  if (!recovering || next.consecutiveOk >= recoverOn) next.status = 'HEALTHY';
  else next.status = 'DEGRADED';
  return next;
}

// ---- Incident derivation from component transitions ----
export function reconcileIncidents(prevIncidents, componentStates, policy, meta = {}) {
  const open = new Map((prevIncidents || []).filter((i) => i.status === 'OPEN').map((i) => [i.componentId, i]));
  const resolved = (prevIncidents || []).filter((i) => i.status === 'RESOLVED');
  const now = meta.ts || null;
  const out = [...resolved];
  for (const [cid, st] of Object.entries(componentStates)) {
    const bad = st.status === 'DOWN' || st.status === 'DEGRADED';
    const cur = open.get(cid);
    if (bad && !cur) {
      out.push({
        id: `inc-${cid}-${meta.runId || 'run'}`, componentId: cid, edgeId: null,
        journeys: affectedJourneys(cid, policy), severity: st.status === 'DOWN' ? 'P1' : 'P2',
        status: 'OPEN', startedAt: now, firstBad: st.lastFailure || now, lastBad: st.lastFailure || now,
        lastGood: st.lastGood || null, release: meta.release || null, build: meta.build ?? null,
        errorCode: st.errorCode || null, summary: `${cid} ${st.status}`,
      });
    } else if (bad && cur) {
      cur.lastBad = st.lastFailure || cur.lastBad; cur.errorCode = st.errorCode || cur.errorCode;
      cur.severity = st.status === 'DOWN' ? 'P1' : cur.severity; out.push(cur); open.delete(cid);
    } else if (!bad && cur) {
      cur.status = 'RESOLVED'; cur.resolvedAt = now; cur.lastGood = st.lastGood || now; out.push(cur); open.delete(cid);
    }
  }
  for (const cur of open.values()) out.push(cur); // untouched still-open
  return out;
}

// ---- Snapshot builder ----
export function buildSnapshot({ componentStates, edges, policy, incidents, ciEvidence, meta }) {
  const componentStatus = {};
  const componentErrorCodes = {};
  for (const [id, st] of Object.entries(componentStates)) {
    componentStatus[id] = st.status;
    componentErrorCodes[id] = st.errorCode || null;
  }
  const journeys = computeJourneys(componentStatus, policy);
  const overall = computeOverall(journeys, policy.criticalJourneys || []);
  const edgeStatuses = {};
  for (const [id, s] of Object.entries(computeEdges(componentStatus, edges || []))) edgeStatuses[id] = { status: s };
  const blockers = releaseBlockers(policy, journeys, ciEvidence || {}, { componentStatus, componentErrorCodes, currentScopeHashes: meta.currentScopeHashes || {} });
  const platforms = platformReadiness({ blockers }, policy);
  return {
    generatedAt: meta.ts || null, runId: meta.runId || null, environment: meta.environment || 'unknown',
    release: meta.release || null, build: meta.build ?? null, minSupportedBuild: meta.minSupportedBuild ?? null,
    overall,
    components: componentStates,
    edges: edgeStatuses,
    journeys,
    incidents: incidents || [],
    ciEvidence: ciEvidence || {},
    blockers,
    platforms,
  };
}

// ---- Release gate ----
function platformsOf(componentId, policy) {
  const sc = componentId && policy.platform && policy.platform.componentScope && policy.platform.componentScope[componentId];
  return sc && sc.length ? sc : ['ios', 'android'];
}

// Returns ALL release items (blocking + warnings). severity (P0/P1/P2) is SEPARATE
// from releaseBlocking (boolean): P0 defaults blocking, P1 per-policy, P2 warning.
// Readiness/exit are driven by releaseBlocking, NOT by severity counts. Deduped by id.
export function releaseBlockers(policy, journeyResults, ciEvidence, opts = {}) {
  const items = [];
  const componentStatus = opts.componentStatus || {};
  const currentScope = opts.currentScopeHashes || {};
  const rg = policy.releaseGate || {};
  const add = (o) => items.push({ platforms: platformsOf(o.componentId, policy), journeys: [], resolution: null, componentId: null, ...o });

  // static architecture risks — ALL surfaced; non-blockers become warnings
  for (const r of policy.staticRisks || []) {
    add({ id: r.id, severity: r.severity || 'P2', releaseBlocking: r.releaseBlocker === true, title: r.title, source: 'static-architecture-risk', componentId: r.componentId || null, journeys: r.journeys || [], resolution: r.resolution || null });
  }
  // live deployment drift (triggered by the live check). A blocker may match on
  // component status (triggersOnStatus) and/or the check's errorCode
  // (triggersOnErrorCode). With neither field it falls back to the legacy
  // "DEGRADED/DOWN" rule. errorCode matching lets us separate e.g. a RULES_DENY
  // rules-drift from an APPCONFIG_MISSING config gap on an otherwise-HEALTHY node.
  const componentErr = opts.componentErrorCodes || {};
  for (const d of policy.liveDriftBlockers || []) {
    const cs = componentStatus[d.componentId];
    const ec = componentErr[d.componentId] || null;
    let fire;
    if (d.triggersOnStatus || d.triggersOnErrorCode) {
      const stOk = !d.triggersOnStatus || d.triggersOnStatus.includes(cs);
      const ecOk = !d.triggersOnErrorCode || d.triggersOnErrorCode.includes(ec);
      fire = stOk && ecOk;
    } else {
      fire = cs === 'DEGRADED' || cs === 'DOWN';
    }
    if (fire) add({ id: d.id, severity: d.severity || 'P1', releaseBlocking: d.releaseBlocker !== false, title: d.title, source: 'live-drift', componentId: d.componentId, journeys: d.journeys || [], resolution: d.resolution || null });
  }
  // CI invariants: must be PASS AND scope-fresh (scoped fingerprint, not whole-repo HEAD)
  for (const inv of rg.requiredCiInvariants || []) {
    const e = ciEvidence[inv];
    if (!e || e.status !== 'PASS') { add({ id: `ci-${inv}`, severity: 'P0', releaseBlocking: true, title: `CI invariant ${inv} = ${e ? e.status : 'MISSING'}`, source: 'ci-invariant' }); continue; }
    if (rg.scopedFreshness) {
      const f = evidenceFresh(e, currentScope[inv]);
      if (!f.fresh) add({ id: `ci-${inv}-stale`, severity: 'P0', releaseBlocking: true, title: `CI invariant ${inv} PASS but ${f.reason}`, source: 'ci-stale' });
    }
  }
  // release-critical journeys: DOWN => P0 blocking; UNKNOWN (not verified) => P1 blocking
  for (const jd of policy.releaseCriticalJourneys || []) {
    const s = journeyResults[jd] && journeyResults[jd].status;
    if (s === 'DOWN') add({ id: `live-${jd}`, severity: 'P0', releaseBlocking: true, title: `Release-critical journey ${jd} = DOWN`, source: 'live-check', journeys: [jd] });
    else if (rg.releaseCriticalUnknownBlocks && (s === 'UNKNOWN' || s == null)) add({ id: `unverified-${jd}`, severity: rg.unknownCriticalSeverity || 'P1', releaseBlocking: true, title: `Release-critical journey ${jd} = UNKNOWN (not verified)`, source: 'not-verified', journeys: [jd] });
  }
  // dedupe by id (first wins)
  const seen = new Map();
  for (const it of items) if (!seen.has(it.id)) seen.set(it.id, it);
  return [...seen.values()];
}

// Per-platform readiness: only RELEASE-BLOCKING items scoped to that platform count.
export function platformReadiness(snapshot, policy) {
  const out = {};
  for (const p of ['ios', 'android']) {
    const bl = (snapshot.blockers || []).filter((x) => x.releaseBlocking && (x.platforms || ['ios', 'android']).includes(p));
    const p0 = bl.filter((x) => x.severity === 'P0'), p1 = bl.filter((x) => x.severity === 'P1');
    out[p] = { ready: bl.length === 0, verdict: bl.length ? 'BLOCKED' : 'READY', blocking: bl.length, p0: p0.length, p1: p1.length, blockers: bl };
  }
  return out;
}

export function releaseReadiness(snapshot, policy) {
  const all = snapshot.blockers || [];
  const blocking = all.filter((x) => x.releaseBlocking);
  const warnings = all.filter((x) => !x.releaseBlocking);
  const platforms = platformReadiness(snapshot, policy);
  const anyBlocked = !platforms.ios.ready || !platforms.android.ready;
  return {
    readyForIOS: platforms.ios.ready, readyForAndroid: platforms.android.ready,
    platforms, blocking, warnings,
    p0Blockers: blocking.filter((x) => x.severity === 'P0'), p1Blockers: blocking.filter((x) => x.severity === 'P1'),
    verdict: anyBlocked ? 'NOT READY' : warnings.length ? 'READY WITH WARNINGS' : 'READY',
    exitCode: anyBlocked ? 1 : 0,
  };
}
