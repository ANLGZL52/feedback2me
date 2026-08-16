// Read-only Railway runtime-log collector (Runtime Observability Phase 2).
// Fetches a BOUNDED window of the feedback2me deployment logs via the Railway
// Public API and normalizes them into PII-safe backend runtime events. It NEVER
// mirrors raw logs — only lines that match a known-safe shape become events, and
// every emitted message is redacted. Missing token -> UNKNOWN/NOT_CONFIGURED
// (a missing observability credential is NOT a backend outage).
//
// This is a LOG COLLECTOR, distinct from health checks: it answers "what happened
// inside the app", not "is it reachable". It never marks a component DOWN.
//
// Credential: OPS_RAILWAY_TOKEN (a dedicated Railway token). Never logged.
// Injectable `fetchLogs` (deps) so tests never hit the network.

const RAILWAY_API = 'https://backboard.railway.com/graphql/v2';
const PROJECT = '07167eda-b01e-4c71-97f2-a11f01d8ebc3';
const ENV = '5b27351b-e3a5-47f1-92cb-e50a5fb9eb63';
const SERVICE = '2626cd91-87a8-4a84-913f-4336477fd523'; // feedback2me
export const DEFAULT_LIMIT = 200;      // bounded window — never fetch unbounded
export const DEFAULT_TIMEOUT_MS = 8000; // never hang the workflow

// Redact any secret/PII material from a message before it can become an event.
export function redact(input) {
  let s = String(input == null ? '' : input);
  s = s
    .replace(/postgres(?:ql)?:\/\/[^\s"']+/gi, 'postgres://<redacted>')
    .replace(/https?:\/\/[^\s"']*:[^\s"'@]*@[^\s"']+/gi, '<redacted-url>')
    .replace(/eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, '<jwt>')
    .replace(/\bBearer\s+[A-Za-z0-9._-]+/gi, 'Bearer <redacted>')
    .replace(/\b(authorization|cookie|set-cookie|password|token|access[_-]?token|refresh[_-]?token|api[_-]?key|secret|purchase[_-]?token|receipt)\b\s*[:=]\s*[^\s,;}"']+/gi, '$1=<redacted>')
    .replace(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/g, '<email>')
    .replace(/sk-[A-Za-z0-9]{16,}/g, '<key>');
  return s.slice(0, 200); // bound length
}

// Canonicalize a route so a dynamic value (e.g. a private link code) is never logged.
export function canonicalRoute(method, url) {
  if (!url) return null;
  let path = String(url).split('?')[0];
  path = path
    .replace(/\/(links|public\/links|feedbacks|f)\/[^/]+/gi, '/$1/:code')
    .replace(/\/users\/[^/]+/gi, '/users/:id')
    .replace(/\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, '/:uuid')
    .replace(/\/\d{2,}/g, '/:n');
  return `${method || 'GET'} ${path}`;
}

const statusClassOf = (code) => (code >= 500 ? '5xx' : code >= 400 ? '4xx' : code >= 300 ? '3xx' : code >= 200 ? '2xx' : null);

// Normalize ONE Railway log line -> a safe runtime event, or null if not recognized.
// Accepts structured JSON lines (from the future Fastify instrumentation) and a
// small set of known plaintext startup/error lines. Everything else -> null (ignored).
export function normalizeLogLine(line, meta = {}) {
  const base = { timestamp: (line && line.timestamp) || meta.timestamp || null, source: 'monitor', service: 'feedback2me',
    environment: meta.environment || 'production', deploymentId: meta.deploymentId || null };
  const raw = line && line.message;
  if (raw == null) return null;

  // 1) Structured JSON runtime event (from server instrumentation).
  const trimmed = String(raw).trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    let obj = null; try { obj = JSON.parse(trimmed); } catch { obj = null; }
    if (obj && typeof obj === 'object' && typeof obj.evt === 'string') {
      // Only copy ALLOW-LISTED safe fields — never arbitrary payload.
      return {
        ...base, eventType: obj.evt, severity: obj.level || (line.severity || 'info'),
        method: obj.method || null,
        routeId: obj.route ? canonicalRoute(obj.method, obj.route) : null,
        statusClass: typeof obj.status === 'number' ? statusClassOf(obj.status) : (obj.statusClass || null),
        latencyMs: typeof obj.ms === 'number' ? obj.ms : null,
        errorCode: obj.code || null,
        correlationId: obj.cid || null,
        componentId: obj.component || null,
        provider: obj.provider || null,
        dbOperationCategory: obj.dbOp || null,
        retryable: typeof obj.retryable === 'boolean' ? obj.retryable : null,
      };
    }
    return null; // unknown JSON shape -> ignore
  }

  // 2) Known plaintext lines (current production emits only these).
  const msg = redact(trimmed);
  if (/^listening\b/i.test(trimmed) || /listening http/i.test(trimmed)) {
    return { ...base, eventType: 'server.startup.ok', severity: 'info', componentId: 'node-railway-api', errorCode: null };
  }
  if (/^FATAL:/i.test(trimmed) || /JWT_SECRET is missing/i.test(trimmed)) {
    return { ...base, eventType: 'server.startup.error', severity: 'error', componentId: 'node-railway-api', errorCode: 'INTERNAL_ERROR' };
  }
  if ((line.severity || '').toLowerCase() === 'error' || /\b(error|exception|unhandled)\b/i.test(trimmed)) {
    return { ...base, eventType: 'server.runtime.error', severity: 'error', componentId: 'node-railway-api', errorCode: 'INTERNAL_ERROR', message: msg };
  }
  return null; // ordinary infra/info line -> ignored (high-signal only)
}

async function defaultFetchLogs(token, limit, timeoutMs) {
  const ctrl = new AbortController();
  const to = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const gql = async (query, variables) => {
      const res = await fetch(RAILWAY_API, { method: 'POST', signal: ctrl.signal,
        headers: { 'Content-Type': 'application/json', 'Project-Access-Token': token },
        body: JSON.stringify({ query, variables }) });
      return { status: res.status, json: await res.json().catch(() => null) };
    };
    const dq = await gql(`query($input: DeploymentListInput!){ deployments(first:1, input:$input){ edges { node { id } } } }`,
      { input: { projectId: PROJECT, environmentId: ENV, serviceId: SERVICE } });
    if (dq.status === 401 || dq.status === 403) return { auth: 'FAILED', logs: null };
    const depId = dq.json?.data?.deployments?.edges?.[0]?.node?.id;
    if (!depId) return { auth: 'OK', logs: [], deploymentId: null };
    const lq = await gql(`query($id:String!,$limit:Int){ deploymentLogs(deploymentId:$id, limit:$limit){ timestamp message severity } }`,
      { id: depId, limit });
    if (lq.status === 401 || lq.status === 403) return { auth: 'FAILED', logs: null };
    return { auth: 'OK', logs: lq.json?.data?.deploymentLogs || [], deploymentId: depId };
  } finally { clearTimeout(to); }
}

export async function collect(opts = {}, deps = {}) {
  const token = opts.token || process.env.OPS_RAILWAY_TOKEN;
  if (!token) return { status: 'UNKNOWN', errorCode: 'NOT_CONFIGURED', events: [], note: 'OPS_RAILWAY_TOKEN not configured' };
  const limit = Math.min(opts.limit || DEFAULT_LIMIT, DEFAULT_LIMIT);
  const timeoutMs = opts.timeoutMs || DEFAULT_TIMEOUT_MS;
  const fetchLogs = deps.fetchLogs || defaultFetchLogs;
  let r;
  try { r = await fetchLogs(token, limit, timeoutMs); }
  catch (e) { return { status: 'DOWN', errorCode: e && e.name === 'AbortError' ? 'TIMEOUT' : 'COLLECTOR_ERROR', events: [] }; }
  if (!r || r.auth === 'FAILED') return { status: 'DOWN', errorCode: 'RAILWAY_AUTH_FAILED', events: [] };
  const meta = { deploymentId: r.deploymentId || null };
  const events = (r.logs || []).map((l) => normalizeLogLine(l, meta)).filter(Boolean);
  return { status: 'HEALTHY', errorCode: null, deploymentId: r.deploymentId || null,
    logLinesScanned: (r.logs || []).length, events };
}
