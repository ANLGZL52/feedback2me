// Read-only topology dashboard — MODEL. Joins the static topology (nodes/edges) with the
// live status derived from ops-status artifacts, and provides the graph traversals the UI
// needs (dependencies, downstream impact, path trace). Pure functions; unit-tested.
import { NODES } from '../topology/nodes.js';
import { EDGES } from '../topology/edges.js';
import { deepRedact } from './sanitizer.mjs';

// ---- status normalization ----
const GREEN = new Set(['HEALTHY', 'FULL', 'VERIFIED', 'LIVE', 'PASS', 'OK']);
const AMBER = new Set(['WARN', 'PARTIAL', 'DEFERRED', 'IDLE', 'DEGRADED']);
const RED = new Set(['CRITICAL', 'BLOCK', 'UNHEALTHY', 'DOWN', 'FAILED', 'UNAVAILABLE']);
const GREY = new Set(['UNKNOWN', 'NOT_CONFIGURED', 'N/A', 'NA', '']);

export function normalizeStatus(raw) {
  const s = (raw == null ? 'N/A' : String(raw)).toUpperCase().trim();
  const status = s === '' ? 'N/A' : s;
  let severity = 'grey';
  if (GREEN.has(status)) severity = 'green';
  else if (RED.has(status)) severity = 'red';
  else if (AMBER.has(status)) severity = 'amber';
  else if (GREY.has(status)) severity = 'grey';
  else severity = 'grey'; // unknown label -> grey (never fabricate green)
  return { status, severity };
}

const dom = (health, key) => (health && health.domains && health.domains[key]) || null;

// ---- per-node live status + key metric from artifacts ----
export function statusForNode(node, art) {
  const src = node.statusSource || { kind: 'na' };
  const h = art.health;
  switch (src.kind) {
    case 'na': return 'N/A';
    case 'const': return src.value;
    case 'field': return (h && h[src.key]) || 'UNKNOWN';
    case 'domain': { const d = dom(h, src.key); return d ? (d.status || 'UNKNOWN') : 'UNKNOWN'; }
    case 'gate': return (h && h.productReleaseGate && h.productReleaseGate.status) || 'UNKNOWN';
    case 'deferred': return (h && h.validationEvidence && h.validationEvidence.realIapE2E) || 'DEFERRED';
    case 'incident': {
      const a = art.incidentActions;
      const mode = a && (a.mode || (a.deliveryHealth && a.deliveryHealth.deliveryMode));
      return mode || 'UNKNOWN';
    }
    case 'digest': {
      const d = art.digestDelivery;
      return d ? (d.health || 'UNKNOWN') : 'UNKNOWN';
    }
    case 'digestChannel': {
      const d = art.digestDelivery;
      if (!d) return 'UNKNOWN';
      if (d.health === 'NOT_CONFIGURED') return 'NOT_CONFIGURED';
      return d.channel === 'slack' ? 'LIVE' : 'UNKNOWN';
    }
    default: return 'UNKNOWN';
  }
}

export function metricForNode(node, art) {
  const m = node.metric;
  if (!m) return null;
  const h = art.health;
  const val = (label, value, unit) => (value == null ? { label, value: 'N/A', unit: '' } : { label, value, unit: unit || '' });
  switch (m.kind) {
    case 'domainField': { const d = dom(h, m.key); const v = d && d.metrics ? d.metrics[m.field] : (d ? d[m.field] : null); return val(m.label, v ?? null, m.unit); }
    case 'domainLatencyP95': { const d = dom(h, m.key); const v = d && d.metrics && d.metrics.latencyMs ? d.metrics.latencyMs.p95 : null; return val(m.label, v ?? null, m.unit); }
    case 'collectorFreshness': { const f = h && h.collectorFreshness; return val(m.label, f && f.ageMinutes != null ? f.ageMinutes : null, m.unit); }
    case 'activeIncidents': { const s = art.incidentState; const n = s && Array.isArray(s.incidents) ? s.incidents.filter((i) => i.state === 'OPEN').length : 0; return val(m.label, n, m.unit); }
    default: return null;
  }
}

// ---- graph adjacency + traversal ----
const outgoing = (id) => EDGES.filter((e) => e.source === id);
const incoming = (id) => EDGES.filter((e) => e.target === id);

export function dependsOn(id) { return incoming(id).map((e) => e.source); }      // upstream
export function usedBy(id) { return outgoing(id).map((e) => e.target); }          // downstream direct
export function observedBy(id) { return outgoing(id).filter((e) => e.type === 'OBSERVES' || e.type === 'AUTH').map((e) => e.target); }

// BFS closure downstream (failure impact) — everything reachable via outgoing edges.
export function downstreamClosure(id) {
  const seen = new Set(); const q = [id];
  while (q.length) { const cur = q.shift(); for (const e of outgoing(cur)) if (!seen.has(e.target)) { seen.add(e.target); q.push(e.target); } }
  seen.delete(id); return [...seen];
}
// BFS closure upstream (all dependencies).
export function upstreamClosure(id) {
  const seen = new Set(); const q = [id];
  while (q.length) { const cur = q.shift(); for (const e of incoming(cur)) if (!seen.has(e.source)) { seen.add(e.source); q.push(e.source); } }
  seen.delete(id); return [...seen];
}

// Shortest path (edge list) between two nodes following edge direction; [] if none.
export function pathTrace(from, to) {
  if (from === to) return [];
  const prev = new Map(); const q = [from]; const seen = new Set([from]);
  while (q.length) {
    const cur = q.shift();
    for (const e of outgoing(cur)) {
      if (!seen.has(e.target)) { seen.add(e.target); prev.set(e.target, e); if (e.target === to) { return rebuild(prev, to); } q.push(e.target); }
    }
  }
  return [];
}
function rebuild(prev, to) { const path = []; let cur = to; while (prev.has(cur)) { const e = prev.get(cur); path.unshift(e); cur = e.source; } return path; }

// ---- assembled payloads ----
export function buildTopology(art) {
  const nodes = NODES.map((n) => {
    const raw = statusForNode(n, art);
    const { status, severity } = normalizeStatus(raw);
    return { id: n.id, label: n.label, category: n.category, role: n.role, x: n.x, y: n.y, status, severity, metric: metricForNode(n, art) };
  });
  // edge severity inherits from its SOURCE node status (amber/red paths light up).
  const nodeSev = Object.fromEntries(nodes.map((n) => [n.id, n.severity]));
  const edges = EDGES.map((e) => ({
    id: e.id, source: e.source, target: e.target, type: e.type, animated: !!e.animated,
    severity: nodeSev[e.source] || 'grey',
    purpose: e.purpose || '', input: e.input || '', output: e.output || '',
    security: e.security || '', failure: e.failure || '', observability: e.observability || '',
  }));
  return deepRedact({ nodes, edges });
}

export function buildMeta(art) {
  const h = art.health || {};
  const active = art.incidentState && Array.isArray(art.incidentState.incidents)
    ? art.incidentState.incidents.filter((i) => i.state === 'OPEN').length : 0;
  const fresh = h.collectorFreshness && h.collectorFreshness.ageMinutes != null ? h.collectorFreshness.ageMinutes : null;
  const dc = h.deploymentContext || {};
  return deepRedact({
    present: art.present,
    environment: 'local (read-only)',
    branch: dc.branch || 'main',
    commit: dc.commit || null,
    build: dc.build || null,
    workflowRun: dc.runId || dc.workflowRun || null,
    artifactTimestamp: art.artifactTimestamp,
    runtime: h.currentRuntimeHealth || 'UNKNOWN',
    observabilityPlatform: h.observabilityPlatformStatus || 'UNKNOWN',
    runtimeValidation: h.runtimeValidationStatus || 'UNKNOWN',
    gate: (h.productReleaseGate && h.productReleaseGate.status) || 'UNKNOWN',
    realIapE2E: (h.validationEvidence && h.validationEvidence.realIapE2E) || 'DEFERRED',
    activeCritical: active,
    collectorFreshnessMin: fresh,
    incidentMode: (art.incidentActions && (art.incidentActions.mode)) || 'UNKNOWN',
    digestHealth: (art.digestDelivery && art.digestDelivery.health) || 'UNKNOWN',
    digestChannel: (art.digestDelivery && art.digestDelivery.channel) || null,
  });
}

// Node detail: static metadata + live status + neighbors + impact + its domain events.
export function buildNodeDetail(id, art) {
  const def = NODES.find((n) => n.id === id);
  if (!def) return null;
  const raw = statusForNode(def, art);
  const { status, severity } = normalizeStatus(raw);
  const label = (ids) => ids.map((x) => { const nn = NODES.find((n) => n.id === x); return nn ? { id: nn.id, label: nn.label, category: nn.category } : { id: x, label: x }; });
  const domainKey = def.statusSource && def.statusSource.kind === 'domain' ? def.statusSource.key : null;
  const evDomain = domainKey || domainFromNode(id);
  const events = art.events.filter((e) => !evDomain || e.domain === evDomain).slice(0, 40);
  return deepRedact({
    id: def.id, label: def.label, category: def.category, role: def.role, description: def.description,
    status, severity, metric: metricForNode(def, art),
    dependsOn: label(dependsOn(id)),
    usedBy: label(usedBy(id)),
    observedBy: label(observedBy(id)),
    downstreamImpact: label(downstreamClosure(id)),
    alertCodes: def.alertCodes || [],
    runbook: def.runbook || [],
    sources: def.sources || [],
    recentEvents: events,
    lastUpdate: art.artifactTimestamp,
  });
}

function domainFromNode(id) {
  if (id.startsWith('iap') || ['premium_product', 'apple_verification', 'processed_purchases', 'paid_link_credits', 'app_store'].includes(id)) return 'IAP';
  if (id === 'openai' || id === 'ai_summary') return 'OPENAI';
  if (id === 'railway') return 'RAILWAY';
  if (id === 'postgres') return 'POSTGRES';
  if (id === 'collector') return 'COLLECTOR';
  if (id === 'incident_engine' || id === 'github_issues') return 'INCIDENT';
  if (id === 'daily_digest' || id === 'slack') return 'SLACK';
  if (id === 'security_domain' || id === 'wif') return 'SECURITY';
  if (id === 'service_domain') return 'SERVICE';
  return null;
}

export { NODES, EDGES };
