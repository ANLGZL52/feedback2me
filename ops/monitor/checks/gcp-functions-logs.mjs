// Read-only GCP / Firebase Cloud Functions log collector (Runtime Observability
// Phase 3). Queries Cloud Logging (Logging v2 entries.list) for a BOUNDED, recent,
// function-scoped window and normalizes entries into PII-safe gcp.function.* events.
//
// PROVEN STATE (2026-08-16): no Cloud Function is deployed for feedbacktome-79655
// (iapVerify callable URL = 404) and no read-only GCP identity is configured, so
// this collector is FOUNDATION — it activates once (a) a function is deployed and
// (b) a least-privilege GCP identity (WIF preferred) provides GCP_ACCESS_TOKEN.
//
// SAFETY: raw textPayload / jsonPayload / stack traces are DROPPED after
// classification — only allow-listed safe fields are emitted. Bounded query, small
// page size, NO pagination loop, timeout. Missing token -> UNKNOWN/NOT_CONFIGURED
// (not a function outage); 403 -> DOWN/GCP_PERMISSION_DENIED (a collector-auth
// problem, NOT a Cloud Function outage).

const LOGGING_API = 'https://logging.googleapis.com/v2/entries:list';
export const DEFAULT_PAGE_SIZE = 50;   // bounded — never a project-wide dump
export const DEFAULT_TIMEOUT_MS = 8000;
export const DEFAULT_LOOKBACK_MIN = 30; // recent window only (cost control)
const PROJECT = 'feedbacktome-79655';

// Map a Cloud Logging severity + message to a STABLE safe error category.
export function classifyGcp(entry) {
  const sev = String(entry.severity || 'DEFAULT').toUpperCase();
  const msg = String(
    (entry.jsonPayload && (entry.jsonPayload.message || entry.jsonPayload.error)) ||
    entry.textPayload || '',
  );
  let errorCode = null;
  if (sev === 'ERROR' || sev === 'CRITICAL' || sev === 'ALERT' || sev === 'EMERGENCY') {
    if (/timeout|deadline/i.test(msg)) errorCode = 'FUNCTION_TIMEOUT';
    else if (/permission|forbidden|denied|unauthorized/i.test(msg)) errorCode = 'FUNCTION_PERMISSION_DENIED';
    else if (/unavailable|econnrefused|enotfound/i.test(msg)) errorCode = 'FUNCTION_UNAVAILABLE';
    else if (/invalid|validation|invalid-argument/i.test(msg)) errorCode = 'FUNCTION_VALIDATION_ERROR';
    else errorCode = 'FUNCTION_RUNTIME_ERROR';
  }
  const eventType = errorCode ? 'gcp.function.error'
    : sev === 'WARNING' ? 'gcp.function.warning'
    : 'gcp.function.execution';
  return { eventType, errorCode, severity: sev.toLowerCase() };
}

// Extract a safe function/service name + region from an entry's resource labels.
function resourceInfo(entry) {
  const r = entry.resource || {};
  const l = r.labels || {};
  // 1st-gen: resource.type=cloud_function, labels.function_name/region.
  // 2nd-gen: resource.type=cloud_run_revision, labels.service_name/location.
  const name = l.function_name || l.service_name || null;
  const region = l.region || l.location || null;
  return { name, region, resourceType: r.type || null };
}

// --- aiSummary OpenAI structured events ------------------------------------
// The aiSummary function emits PII-safe structured events (see
// functions/src/ai-core.ts buildObsEvent) via console.log(JSON.stringify(...)),
// which Cloud Logging surfaces in jsonPayload (or, occasionally, a JSON string
// in textPayload). We preserve ONLY an explicit allow-list of operational
// metadata — NEVER prompt / feedback / completion / key / token / uid / raw
// payload. The output object is BUILT from the allow-list, never copied from the
// source and pruned, so unknown/sensitive fields cannot leak by accident.
const OPENAI_EVENT_TYPES = new Set([
  'openai.request.completed',
  'openai.request.failed',
  'openai.rate_limited',
  'openai.timeout',
  'openai.fallback.required',
]);

function numOrNull(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null; // malformed numeric -> null (never throws)
}
function safeStr(v, max) {
  return typeof v === 'string' && v.length ? v.slice(0, max) : null; // bounded; drops non-strings
}

// Locate the structured JSON payload of a log entry, if any.
function payloadObject(entry) {
  const jp = entry.jsonPayload;
  if (jp && typeof jp === 'object' && !Array.isArray(jp)) return jp;
  const tp = entry.textPayload;
  if (typeof tp === 'string') {
    const s = tp.trim();
    if (s.length > 1 && s.length < 20000 && s[0] === '{' && s[s.length - 1] === '}') {
      try {
        const o = JSON.parse(s);
        if (o && typeof o === 'object' && !Array.isArray(o)) return o;
      } catch { /* not JSON -> ignore */ }
    }
  }
  return null;
}

// Extract allow-listed OpenAI metadata from an aiSummary event, or null.
export function extractOpenAiMeta(entry) {
  const p = payloadObject(entry);
  if (!p) return null;
  // Only our own aiSummary provider events — never arbitrary jsonPayloads.
  if (p.source !== 'functions' || p.service !== 'aiSummary') return null;
  if (typeof p.eventType !== 'string' || !OPENAI_EVENT_TYPES.has(p.eventType)) return null;
  return {
    eventType: p.eventType,
    errorCode: safeStr(p.errorCode, 40), // e.g. OPENAI_RATE_LIMITED | null
    // Allow-listed metrics/ids ONLY — explicit fields, no spread.
    metrics: {
      statusClass: safeStr(p.statusClass, 8),
      model: safeStr(p.model, 40),
      latencyMs: numOrNull(p.latencyMs),
      openaiProcessingMs: numOrNull(p.openaiProcessingMs),
      inputTokens: numOrNull(p.inputTokens),
      outputTokens: numOrNull(p.outputTokens),
      totalTokens: numOrNull(p.totalTokens),
      openaiRequestId: safeStr(p.openaiRequestId, 64),
      clientRequestId: safeStr(p.clientRequestId, 64),
    },
  };
}

// --- iapVerify IAP structured events ---------------------------------------
// The iapVerify callable emits PII-safe structured events (see
// functions/src/iap-core.ts buildIapObsEvent). We preserve ONLY an explicit
// allow-list of operational metadata — NEVER receipt / verificationData /
// purchaseToken / raw transactionId / uid / email / secret. Built field-by-field
// from the allow-list (never a source copy+prune), so sensitive fields cannot
// leak by accident. productId + sanitized platform are app-level categories.
const IAP_EVENT_TYPES = new Set([
  'iap.verify.started',
  'iap.verify.apple.success',
  'iap.verify.apple.rejected',
  'iap.verify.apple.transient_failure',
  'iap.verify.android.success',
  'iap.verify.android.rejected',
  'iap.verify.android.transient_failure',
  'iap.verify.android_disabled',
  'iap.credit.granted',
  'iap.credit.replay',
  'iap.verify.invalid_product',
  'iap.verify.error',
]);

function boolOrNull(v) {
  return typeof v === 'boolean' ? v : null;
}

// Extract allow-listed IAP metadata from an iapVerify event, or null.
export function extractIapMeta(entry) {
  const p = payloadObject(entry);
  if (!p) return null;
  // Only our own iapVerify provider events — never arbitrary jsonPayloads.
  if (p.source !== 'functions' || p.service !== 'iapVerify') return null;
  if (typeof p.eventType !== 'string' || !IAP_EVENT_TYPES.has(p.eventType)) return null;
  return {
    eventType: p.eventType,
    errorCode: safeStr(p.errorCode, 48), // e.g. apple_status_21002 | ANDROID_VERIFICATION_NOT_CONFIGURED | null
    provider: safeStr(p.provider, 16), // apple | android | null
    // Allow-listed metrics/ids ONLY — explicit fields, no spread.
    metrics: {
      platform: safeStr(p.platform, 16), // ios|apple|android|google|other
      productId: safeStr(p.productId, 48), // app-level product id (not PII)
      resultClass: safeStr(p.resultClass, 16),
      latencyMs: numOrNull(p.latencyMs),
      creditDelta: numOrNull(p.creditDelta), // 0 | 1
      replay: boolOrNull(p.replay),
      clientRequestId: safeStr(p.clientRequestId, 64), // per-op random id (NOT a uid)
      txCorrelation: safeStr(p.txCorrelation, 32), // one-way hash (NOT the raw tx id)
    },
  };
}

// Normalize ONE Cloud Logging entry -> a safe event, or null to drop.
// Raw payload/stack is NEVER emitted — only allow-listed metadata + a safe code.
export function normalizeLogEntry(entry, opts = {}) {
  if (!entry || typeof entry !== 'object') return null;
  const { name, region, resourceType } = resourceInfo(entry);
  // Ignore unrelated GCP services: only cloud_function / cloud_run_revision.
  if (resourceType && resourceType !== 'cloud_function' && resourceType !== 'cloud_run_revision') return null;
  if (opts.functionAllowList && name && !opts.functionAllowList.includes(name)) return null;
  const { eventType, errorCode, severity } = classifyGcp(entry);
  const labels = entry.labels || {};
  const out = {
    timestamp: entry.timestamp || entry.receiveTimestamp || null,
    source: 'gcp-functions', service: name || 'unknown-function', region,
    eventType, severity, errorCode,
    resourceType: resourceType || null,
    gcpExecutionId: labels.execution_id || labels['run.googleapis.com/execution_id'] || null,
    revision: labels.revision_name || (entry.resource && entry.resource.labels && entry.resource.labels.revision_name) || null,
    componentId: 'node-cloud-functions',
    // NOTE: raw textPayload / jsonPayload / stack are intentionally NOT included.
  };
  // aiSummary OpenAI events: overlay the safe provider eventType/errorCode and a
  // strictly allow-listed `openai` metadata object. Generic GCP logs are untouched.
  const oai = extractOpenAiMeta(entry);
  if (oai) {
    out.eventType = oai.eventType;
    out.errorCode = oai.errorCode; // OpenAI-normalized safe code (or null)
    out.provider = 'openai'; // constant we set — not copied from the payload
    out.openai = oai.metrics;
  }
  // iapVerify IAP events: overlay the safe provider eventType/errorCode and a
  // strictly allow-listed `iap` metadata object. Generic GCP logs are untouched.
  const iap = extractIapMeta(entry);
  if (iap) {
    out.eventType = iap.eventType;
    out.errorCode = iap.errorCode; // IAP-normalized safe code (or null)
    out.provider = iap.provider || 'apple'; // apple|android — bounded from payload
    out.iap = iap.metrics;
  }
  return out;
}

async function defaultFetchEntries(token, project, pageSize, lookbackMin, timeoutMs) {
  const ctrl = new AbortController();
  const to = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const sinceIso = new Date(Date.now() - lookbackMin * 60000).toISOString();
    const filter = `(resource.type="cloud_function" OR resource.type="cloud_run_revision") AND timestamp>="${sinceIso}"`;
    const res = await fetch(LOGGING_API, {
      method: 'POST', signal: ctrl.signal,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify({ resourceNames: [`projects/${project}`], filter, pageSize, orderBy: 'timestamp desc' }),
    });
    if (res.status === 401 || res.status === 403) return { auth: 'FAILED', entries: null };
    if (!res.ok) return { auth: 'OK', entries: [], httpStatus: res.status };
    const j = await res.json().catch(() => null);
    return { auth: 'OK', entries: (j && j.entries) || [] }; // single page only — no pagination loop
  } finally { clearTimeout(to); }
}

export async function collect(opts = {}, deps = {}) {
  const token = opts.token || process.env.GCP_ACCESS_TOKEN;
  if (!token) return { status: 'UNKNOWN', errorCode: 'NOT_CONFIGURED', events: [], note: 'GCP_ACCESS_TOKEN not configured (WIF/read-only identity required)' };
  const project = opts.project || PROJECT;
  const pageSize = Math.min(opts.pageSize || DEFAULT_PAGE_SIZE, DEFAULT_PAGE_SIZE);
  const lookbackMin = opts.lookbackMin || DEFAULT_LOOKBACK_MIN;
  const timeoutMs = opts.timeoutMs || DEFAULT_TIMEOUT_MS;
  const fetchEntries = deps.fetchEntries || defaultFetchEntries;
  let r;
  try { r = await fetchEntries(token, project, pageSize, lookbackMin, timeoutMs); }
  catch (e) { return { status: 'DOWN', errorCode: e && e.name === 'AbortError' ? 'TIMEOUT' : 'COLLECTOR_ERROR', events: [] }; }
  if (!r || r.auth === 'FAILED') return { status: 'DOWN', errorCode: 'GCP_PERMISSION_DENIED', events: [] };
  const events = (r.entries || []).map((e) => normalizeLogEntry(e, opts)).filter(Boolean);
  return { status: 'HEALTHY', errorCode: null, entriesScanned: (r.entries || []).length, events };
}
