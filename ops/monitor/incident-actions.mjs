// Observability V4 — incident DECISION ENGINE (transport-agnostic). Pure functions only.
// Turns V3 alerts into deduplicated, cooldown/flapping-guarded incident actions
// (CREATE / REOPEN / UPDATE / RESOLVE / NONE) with stable identity domain+code.
// Knows NOTHING about GitHub — the transport (incident-delivery.mjs) consumes these
// decisions. NEVER emits PII/secrets. Only CRITICAL alerts become incidents.

// Every CRITICAL alert code maps to a RUNBOOK.md section — no incident is ever
// "something failed". WARNING codes are informational and never become incidents.
export const RUNBOOK_SECTIONS = {
  IAP_VERIFY_DOWN: 'IAP_VERIFY_DOWN',
  IAP_LATENCY_DEGRADED: 'IAP_VERIFY_DOWN',
  IAP_MONEY_SAFETY_BREACH: 'IAP_CREDIT_INVARIANT_BREACH',
  IAP_GRANT_DELTA_NOT_ONE: 'IAP_CREDIT_INVARIANT_BREACH',
  IAP_REPLAY_DELTA_NOT_ZERO: 'IAP_CREDIT_INVARIANT_BREACH',
  IAP_CREDIT_UNKNOWN_PRODUCT: 'IAP_CREDIT_INVARIANT_BREACH',
  IAP_INVALID_PRODUCT_CREDITED: 'IAP_CREDIT_INVARIANT_BREACH',
  IAP_CREDIT_AFTER_FAILURE: 'IAP_CREDIT_INVARIANT_BREACH',
  IAP_DUPLICATE_GRANT: 'IAP_CREDIT_INVARIANT_BREACH',
  IAP_SUCCESS_WITHOUT_CREDIT: 'IAP_CREDIT_INVARIANT_BREACH',
  IAP_VERIFY_FAILURE_ELEVATED: 'APPLE_VERIFICATION_FAILURE_SPIKE',
  IAP_TRANSIENT_FAILURE_SUSTAINED: 'APPLE_VERIFICATION_FAILURE_SPIKE',
  IAP_REJECTED_SPIKE: 'APPLE_VERIFICATION_FAILURE_SPIKE',
  OPENAI_DEGRADED: 'OPENAI_PROVIDER_FAILURE',
  OPENAI_LATENCY_DEGRADED: 'OPENAI_PROVIDER_FAILURE',
  POSTGRES_CRITICAL: 'POSTGRES_UNAVAILABLE',
  RAILWAY_5XX_ELEVATED: 'RAILWAY_UNAVAILABLE',
  RAILWAY_UNREACHABLE: 'RAILWAY_UNAVAILABLE',
  COLLECTOR_STALE: 'COLLECTOR_STALE',
  COLLECTOR_RUN_FAILED: 'GCP_WIF_AUTH_FAILED',
  SECRET_OR_PII_LEAK: 'SECRET_OR_PII_LEAK_DETECTED',
  SERVICE_COMPONENT_DOWN: 'SERVICE_COMPONENT_DOWN',
};
export const DOMAIN_LABEL = { IAP: 'domain:iap', OPENAI: 'domain:openai', RAILWAY: 'domain:railway', POSTGRES: 'domain:postgres', COLLECTOR: 'domain:collector', SECURITY: 'domain:security', SERVICE: 'domain:collector', VALIDATION: 'domain:iap', RELEASE: 'domain:iap' };
export const CONTROLLED_LABELS = ['ops', 'severity:critical', 'severity:warning', 'domain:iap', 'domain:openai', 'domain:railway', 'domain:postgres', 'domain:collector', 'domain:security', 'status:ongoing', 'status:resolved'];

// Persistent incident-state schema version (Phase 7). Bump only on a breaking change.
export const INCIDENT_STATE_SCHEMA = 1;

/**
 * Fail-safe reader for persisted incident state (Phases 7/8). Given the RAW file text
 * (or null when absent), returns { incidents, stateTrust, reason }:
 *  - OK        — trusted current/legacy state; use it for dedup.
 *  - DEGRADED  — usable but imperfect (missing file/seed) → lean on GitHub lookup.
 *  - UNTRUSTED — corrupt/incompatible → DROP local incidents (empty) and rely entirely
 *                on the GitHub-side lookup fallback so we never blindly CREATE duplicates.
 * NEVER throws.
 */
export function parseIncidentState(raw) {
  if (raw == null || raw === '') return { incidents: [], stateTrust: 'DEGRADED', reason: 'missing' };
  let obj;
  try { obj = JSON.parse(raw); } catch { return { incidents: [], stateTrust: 'UNTRUSTED', reason: 'invalid_json' }; }
  if (!obj || typeof obj !== 'object' || !Array.isArray(obj.incidents)) return { incidents: [], stateTrust: 'UNTRUSTED', reason: 'wrong_shape' };
  const v = obj.schemaVersion;
  if (v == null) return { incidents: obj.incidents, stateTrust: 'OK', reason: 'legacy_no_version' }; // V4/V5 files pre-date the field
  if (v > INCIDENT_STATE_SCHEMA) return { incidents: [], stateTrust: 'UNTRUSTED', reason: 'future_schema' }; // fail safe
  if (v < INCIDENT_STATE_SCHEMA) return { incidents: obj.incidents, stateTrust: 'OK', reason: 'older_schema' };
  return { incidents: obj.incidents, stateTrust: 'OK', reason: 'current' };
}

/**
 * Incident-delivery subsystem self-health (Phase 9). Pure. No PII/payloads.
 * States: IDLE (armed, nothing to do) · HEALTHY (a write succeeded) · DEGRADED
 * (recoverable trouble — untrusted state, payload rejection, a single lookup/transport
 * miss) · UNAVAILABLE (state missing AND lookup unavailable, or repeated transport loss).
 */
export function computeDeliveryHealth({ mode, actionsNeeded = 0, events = [], failures = 0, stateTrust = 'OK', seedStatus = 'unknown', dedupFallbackUsed = false, now = null }) {
  const nowIso = now ? new Date(now).toISOString() : null;
  const attempts = events.filter((e) => e.event === 'incident.delivery.attempted');
  const successes = events.filter((e) => /created|updated|resolved|reopened/.test(e.event) && e.result === 'ok');
  const transportErrors = events.filter((e) => e.event === 'incident.delivery.transport_error').length;
  const payloadRejections = events.filter((e) => e.event === 'incident.delivery.rejected_payload').length;
  const lookupUnavailable = seedStatus === 'missing' && transportErrors > 0;
  let status;
  if (mode !== 'LIVE') status = 'IDLE';
  else if (transportErrors >= 2 || lookupUnavailable) status = 'UNAVAILABLE';
  else if (failures > 0 || payloadRejections > 0 || stateTrust === 'UNTRUSTED') status = 'DEGRADED';
  else if (successes.length > 0) status = 'HEALTHY';
  else if (actionsNeeded === 0) status = 'IDLE';
  else status = 'HEALTHY';
  return {
    deliveryMode: mode,
    deliveryHealth: status,
    lastDeliveryAttemptAt: attempts.length ? attempts[attempts.length - 1].ts : null,
    lastDeliverySuccessAt: successes.length ? successes[successes.length - 1].ts : null,
    deliveryFailuresWindow: failures,
    deliveryTransportErrors: transportErrors,
    deliveryPayloadRejections: payloadRejections,
    dedupFallbackUsed: !!dedupFallbackUsed,
    stateTrust,
    stateSeedStatus: seedStatus,
    evaluatedAt: nowIso,
  };
}

const idOf = (a) => `${a.domain}:${a.code}`;
const evidenceCount = (a) => { if (!a || !a.evidence) return 0; let s = 0; for (const v of Object.values(a.evidence)) if (typeof v === 'number') s += v; return Math.round(s); };
// Material-change signature (Phase 14): an ONGOING incident only earns an UPDATE when
// one of these low-cardinality facts changes — severity, release gate, deploy, or a
// meaningfully higher evidence count. NOT a per-run comment.
const signatureOf = (a, gateStatus, deployment) => JSON.stringify({ sev: a.severity, gate: gateStatus || null, deploy: deployment || null, ev: evidenceCount(a) });

/**
 * PURE incident decision core. Deterministic given inputs (now = ms epoch).
 * @returns {{incidents:Array, actions:Array}} actions: {action: CREATE|REOPEN|UPDATE|RESOLVE|NONE, ...safe metadata}
 */
export function computeIncidentActions({ alerts = [], prevIncidents = [], config, now, deployment = null, gateStatus = null }) {
  const c = config.incidentDelivery;
  const renotifyMs = c.criticalRenotifyMinutes * 60000;
  const cooldownMs = (c.incidentUpdateCooldownMinutes ?? 30) * 60000;
  const stabilityMs = c.resolvedStabilityMinutes * 60000;
  const flappingMs = c.flappingWindowMinutes * 60000;
  const flapMinT = c.flappingMinTransitions ?? 4;
  const maxPerHour = c.maxIncidentUpdatesPerHour;
  const nowIso = new Date(now).toISOString();

  const crit = alerts.filter((a) => a.severity === 'CRITICAL');
  const prevById = new Map(prevIncidents.map((i) => [i.incidentId, i]));
  const actions = [];
  const out = [];
  const seen = new Set();
  const recentUpdates = (i) => (i.updates || []).filter((u) => now - u < 3600000);

  for (const a of crit) {
    const id = idOf(a);
    seen.add(id);
    const prev = prevById.get(id);
    const runbookSection = RUNBOOK_SECTIONS[a.code] || null;
    const sig = signatureOf(a, gateStatus, deployment);

    if (!prev || prev.state === 'RESOLVED') {
      // NEW, or a re-fire after resolution. Flapping: reuse the recent issue, count transitions.
      const reopen = !!(prev && prev.state === 'RESOLVED' && prev.resolvedAt && now - Date.parse(prev.resolvedAt) < flappingMs);
      const flapHistory = [...((prev && prev.flapHistory) || []), now].filter((t) => now - t < flappingMs);
      const flapping = reopen && flapHistory.length >= flapMinT;
      const startedAt = a.startedAt || nowIso;
      const inc = { incidentId: id, code: a.code, domain: a.domain, severity: 'CRITICAL', runbookSection, startedAt, lastObservedAt: nowIso, resolvedAt: null, durationMs: 0, state: 'OPEN', flapping, deployContextAtStart: a.deployContextAtStart || deployment, latestDeployContext: deployment, issueNumber: reopen ? (prev.issueNumber || null) : null, lastNotifiedAt: nowIso, updates: [now], lastSignature: sig, flapHistory, message: a.message || null };
      actions.push({ action: reopen ? 'REOPEN' : 'CREATE', incidentId: id, code: a.code, domain: a.domain, runbookSection, startedAt, issueNumber: inc.issueNumber, flapping, reason: flapping ? 'flapping' : (reopen ? 'reopen' : 'new') });
      out.push(inc);
    } else {
      // ONGOING — decide UPDATE vs NONE by material change + cooldown + cap; renotify keep-alive.
      const upd = recentUpdates(prev);
      const sinceNotify = prev.lastNotifiedAt ? now - Date.parse(prev.lastNotifiedAt) : Infinity;
      const material = sig !== prev.lastSignature;
      const cooldownOk = sinceNotify >= cooldownMs;
      const renotifyDue = sinceNotify >= renotifyMs;
      const capOk = upd.length < maxPerHour;
      const inc = { ...prev, lastObservedAt: nowIso, clearedSince: null, latestDeployContext: deployment, durationMs: now - Date.parse(prev.startedAt), state: 'OPEN', runbookSection, message: a.message || prev.message || null };
      if (capOk && ((material && cooldownOk) || renotifyDue)) {
        actions.push({ action: 'UPDATE', incidentId: id, code: a.code, domain: a.domain, reason: material ? 'material_change' : 'renotify_interval' });
        inc.lastNotifiedAt = nowIso; inc.updates = [...upd, now]; inc.lastSignature = sig;
      } else {
        actions.push({ action: 'NONE', incidentId: id, code: a.code, reason: !capOk ? 'update_cap' : material ? 'cooldown' : 'no_material_change' });
        inc.updates = upd; // keep prev.lastSignature so a pending material change still fires next cycle
      }
      out.push(inc);
    }
  }

  // Previously-open incidents no longer firing: resolution stability + carry recent RESOLVED (flap memory).
  for (const prev of prevIncidents) {
    if (seen.has(prev.incidentId)) continue;
    if (prev.state === 'RESOLVED') { if (prev.resolvedAt && now - Date.parse(prev.resolvedAt) < flappingMs) out.push(prev); continue; }
    const clearedSince = prev.clearedSince || nowIso;
    if (now - Date.parse(clearedSince) >= stabilityMs) {
      const flapHistory = [...(prev.flapHistory || []), now].filter((t) => now - t < flappingMs);
      const inc = { ...prev, state: 'RESOLVED', resolvedAt: nowIso, clearedSince, durationMs: now - Date.parse(prev.startedAt), flapHistory };
      actions.push({ action: 'RESOLVE', incidentId: prev.incidentId, code: prev.code, domain: prev.domain, issueNumber: prev.issueNumber || null, durationMs: inc.durationMs });
      out.push(inc);
    } else {
      actions.push({ action: 'NONE', incidentId: prev.incidentId, code: prev.code, reason: 'pending_resolution_stability' });
      out.push({ ...prev, clearedSince, state: 'OPEN' });
    }
  }
  return { incidents: out, actions };
}

// ---- safety gate (Phases 8/9): real writes require enabled AND not-dry-run ----
export function deliveryMode(enabled, dryRun) {
  if (enabled && !dryRun) return 'LIVE';
  return dryRun ? 'DRY_RUN' : 'DELIVERY_DISABLED';
}
export const willWriteFor = (mode, action) => mode === 'LIVE' && action !== 'NONE';

// ---- issue rendering (safe metadata only) ----
export function renderIssueBody(inc, ctx = {}) {
  const L = [
    `**Incident:** \`${inc.code}\`  ·  **Domain:** ${inc.domain}  ·  **Severity:** CRITICAL${inc.flapping ? '  ·  **FLAPPING**' : ''}`,
    `**Started:** ${inc.startedAt}  ·  **Last observed:** ${inc.lastObservedAt || inc.startedAt}`,
    inc.resolvedAt ? `**Resolved:** ${inc.resolvedAt}  ·  **Duration:** ${Math.round((inc.durationMs || 0) / 60000)} min` : `**Ongoing** (${Math.round((inc.durationMs || 0) / 60000)} min)`,
    `**Runtime health:** ${ctx.currentRuntimeHealth || '?'}  ·  **Release gate:** ${ctx.productReleaseGate || '?'}`,
    inc.deployContextAtStart ? `**Deploy at start:** commit ${inc.deployContextAtStart.commit || '—'} · build ${inc.deployContextAtStart.build || '—'}` : '',
    inc.message ? `**Signal:** ${String(inc.message).slice(0, 200)}` : '',
    inc.runbookSection ? `**Runbook:** ops/RUNBOOK.md → \`${inc.runbookSection}\`` : '',
    ctx.runUrl ? `**CI run:** ${ctx.runUrl}` : '',
    `\n_Operational metadata only — no user-identifying data or content included._`,
  ];
  return L.filter(Boolean).join('\n');
}
export const issueTitle = (inc) => `[OPS][CRITICAL] ${inc.code}`;
export const issueLabels = (inc) => ['ops', 'severity:critical', DOMAIN_LABEL[inc.domain] || 'domain:iap', inc.resolvedAt ? 'status:resolved' : 'status:ongoing'];

// ---- payload safety validator (Phase 20) ----
// Defense-in-depth: even though renderIssueBody only emits safe fields, NOTHING is
// sent to a transport without passing this. On any hit the transport MUST NOT send
// and must emit INCIDENT_DELIVERY_PAYLOAD_REJECTED.
const PROHIBITED = [
  { name: 'email', re: /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/ },
  { name: 'authorization_header', re: /\b(bearer\s+[A-Za-z0-9._-]+|authorization\s*:)/i },
  { name: 'jwt', re: /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/ },
  { name: 'private_key', re: /BEGIN\s+[A-Z ]*PRIVATE KEY/ },
  { name: 'secret_assignment', re: /\b(api[_-]?key|secret|password|access[_-]?token|refresh[_-]?token|id[_-]?token)\b\s*[:=]\s*\S+/i },
  { name: 'long_base64_blob', re: /[A-Za-z0-9+/]{80,}={0,2}/ },
];
export function validateIssuePayload(title, body) {
  const text = `${title || ''}\n${body || ''}`;
  const violations = PROHIBITED.filter((p) => p.re.test(text)).map((p) => p.name);
  return { safe: violations.length === 0, violations, code: violations.length ? 'INCIDENT_DELIVERY_PAYLOAD_REJECTED' : null };
}
