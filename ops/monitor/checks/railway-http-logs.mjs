// Read-only Railway HTTP-log collector (Runtime Observability Phase 2E).
// Railway's httpLogs is the AUTHORITATIVE request-level source (works even when the
// app's structured stdout events don't reach environmentLogs). We fetch a BOUNDED
// window and normalize each entry into a PII-safe `railway.http.request` event.
//
// PRIVACY: we ONLY SELECT safe fields (timestamp/method/path/httpStatus/
// totalDuration/requestId/deploymentId). srcIp / clientUa / query / headers are
// NEVER requested, so they cannot enter an event. Paths are canonicalized so a
// private link code is never persisted. Missing OPS_RAILWAY_TOKEN -> UNKNOWN/
// NOT_CONFIGURED (not a backend outage); auth fail -> DOWN/RAILWAY_AUTH_FAILED.

const RAILWAY_API = 'https://backboard.railway.com/graphql/v2';
const PROJECT = '07167eda-b01e-4c71-97f2-a11f01d8ebc3';
const ENV = '5b27351b-e3a5-47f1-92cb-e50a5fb9eb63';
const SERVICE = '2626cd91-87a8-4a84-913f-4336477fd523'; // feedback2me
export const DEFAULT_LIMIT = 200;
export const DEFAULT_TIMEOUT_MS = 8000;
export const SUCCESS_SAMPLE_N = 20; // match the backend request-event noise policy

// Canonicalize a path so a dynamic/private value (e.g. a link code) is never stored.
export function canonicalPath(path) {
  if (!path) return 'UNKNOWN_ROUTE';
  let p = String(path).split('?')[0]; // drop query string entirely
  p = p
    .replace(/\/(links|public\/links|feedbacks|f)\/[^/]+/gi, '/$1/:code')
    .replace(/\/users\/[^/]+/gi, '/users/:id')
    .replace(/\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, '/:uuid')
    .replace(/\/\d{2,}/g, '/:n');
  return p || 'UNKNOWN_ROUTE';
}
const statusClassOf = (c) => (c >= 500 ? '5xx' : c >= 400 ? '4xx' : c >= 300 ? '3xx' : c >= 200 ? '2xx' : null);

// Normalize ONE Railway httpLog row -> a safe event (allow-list only). Returns null
// to drop (e.g. successful /health, or an unusable row).
export function normalizeHttpLog(row, meta = {}, counter = { n: 0 }) {
  if (!row || typeof row.httpStatus !== 'number') return null;
  const method = row.method || 'GET';
  const route = canonicalPath(row.path);
  const status = row.httpStatus;
  // Noise policy: 100% of 4xx/5xx; sample successes 1/N; NEVER successful /health.
  if (status < 400) {
    if (route === '/health') return null;
    counter.n += 1;
    if (counter.n % SUCCESS_SAMPLE_N !== 0) return null;
  }
  return {
    timestamp: row.timestamp || meta.timestamp || null,
    source: 'railway-http', service: 'feedback2me', environment: meta.environment || 'production',
    eventType: 'railway.http.request',
    method, routeId: route, statusClass: statusClassOf(status), httpStatus: status,
    latencyMs: typeof row.totalDuration === 'number' ? Math.round(row.totalDuration) : null,
    railwayRequestId: row.requestId || null, // Railway edge id — NOT the Fastify cid
    deploymentId: row.deploymentId || meta.deploymentId || null,
    componentId: 'node-railway-api',
    severity: status >= 500 ? 'error' : status >= 400 ? 'warn' : 'info',
  };
}

async function defaultFetchHttp(token, limit, timeoutMs) {
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
    if (dq.status === 401 || dq.status === 403) return { auth: 'FAILED', rows: null };
    const depId = dq.json?.data?.deployments?.edges?.[0]?.node?.id || null;
    if (!depId) return { auth: 'OK', rows: [], deploymentId: null };
    // ONLY safe fields are selected — srcIp/clientUa/query are never fetched.
    const lq = await gql(`query($id:String!,$n:Int){ httpLogs(deploymentId:$id, beforeLimit:$n){ timestamp method path httpStatus totalDuration requestId deploymentId } }`,
      { id: depId, n: limit });
    if (lq.status === 401 || lq.status === 403) return { auth: 'FAILED', rows: null };
    return { auth: 'OK', rows: lq.json?.data?.httpLogs || [], deploymentId: depId };
  } finally { clearTimeout(to); }
}

export async function collect(opts = {}, deps = {}) {
  const token = opts.token || process.env.OPS_RAILWAY_TOKEN;
  if (!token) return { status: 'UNKNOWN', errorCode: 'NOT_CONFIGURED', events: [], note: 'OPS_RAILWAY_TOKEN not configured' };
  const limit = Math.min(opts.limit || DEFAULT_LIMIT, DEFAULT_LIMIT);
  const timeoutMs = opts.timeoutMs || DEFAULT_TIMEOUT_MS;
  const fetchHttp = deps.fetchHttp || defaultFetchHttp;
  let r;
  try { r = await fetchHttp(token, limit, timeoutMs); }
  catch (e) { return { status: 'DOWN', errorCode: e && e.name === 'AbortError' ? 'TIMEOUT' : 'COLLECTOR_ERROR', events: [] }; }
  if (!r || r.auth === 'FAILED') return { status: 'DOWN', errorCode: 'RAILWAY_AUTH_FAILED', events: [] };
  const meta = { deploymentId: r.deploymentId || null };
  const counter = { n: 0 };
  const events = (r.rows || []).map((row) => normalizeHttpLog(row, meta, counter)).filter(Boolean);
  return { status: 'HEALTHY', errorCode: null, deploymentId: r.deploymentId || null, rowsScanned: (r.rows || []).length, events };
}
