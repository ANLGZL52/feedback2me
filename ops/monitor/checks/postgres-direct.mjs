// Direct read-only PostgreSQL health probe (SELECT 1). Reads the connection
// string ONLY from OPS_POSTGRES_DATABASE_URL (a dedicated observability
// credential — NOT the app's DATABASE_URL, and never hardcoded). No writes.
//
// SECURITY: the connection URI / user / password / host are NEVER emitted. Errors
// are mapped to a small set of safe codes; raw driver messages (which can contain
// the connection string) are never returned or logged.
//
// STATUS: NO credential -> UNKNOWN/NO_CREDENTIAL (a missing observability secret is
// NOT a production outage). SELECT 1 ok within threshold -> HEALTHY; ok but slow ->
// DEGRADED/SLOW; connect/auth/query/timeout failure with a credential set -> DOWN.
//
// TESTABILITY: `deps.connect` (client factory) and `deps.now` are injectable so
// unit tests never touch a real database or require the `pg` driver.

export const DEFAULT_TIMEOUT_MS = 8000;      // bounds connect+query so the runner never hangs
export const DEFAULT_DEGRADED_LATENCY_MS = 2000; // SELECT 1 slower than this -> DEGRADED

function withTimeout(promise, ms, label) {
  let t;
  const timeout = new Promise((_, reject) => { t = setTimeout(() => reject(new Error('OPS_TIMEOUT:' + label)), ms); });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(t));
}

// Map any driver/network error to a safe code — NEVER echo the raw message/URI.
function classifyError(e) {
  const code = e && (e.code || '');
  const msg = (e && e.message) || '';
  if (msg.startsWith('OPS_TIMEOUT:')) return 'TIMEOUT';
  if (code === 'ENOTFOUND' || code === 'EAI_AGAIN') return 'DNS_RESOLUTION_FAILED';
  if (code === 'ECONNREFUSED') return 'CONNECTION_REFUSED';
  if (code === 'ETIMEDOUT') return 'TIMEOUT';
  // Postgres auth failures: 28P01 invalid_password, 28000 invalid_authorization
  if (code === '28P01' || code === '28000') return 'AUTH_FAILED';
  if (code === 'ECONNRESET' || code === 'EPIPE') return 'CONNECTION_FAILED';
  if (code && /^\d{2}[A-Z0-9]{3}$/.test(code)) return 'QUERY_FAILED'; // other SQLSTATE
  return 'CONNECTION_FAILED';
}

// Default connector: lazy-imports `pg` ONLY when a credential is present (so the
// module loads and tests run without the driver installed). SSL is enabled for
// managed Postgres (Railway) unless the URL explicitly sets sslmode=disable.
async function defaultConnect(url, timeoutMs) {
  const mod = await import('pg').catch(() => null);
  if (!mod) { const e = new Error('driver'); e.code = 'OPS_DRIVER'; throw e; }
  const { Client } = mod.default || mod;
  const ssl = /sslmode=disable/.test(url) ? false : { rejectUnauthorized: false };
  const client = new Client({ connectionString: url, ssl, connectionTimeoutMillis: timeoutMs, statement_timeout: timeoutMs, query_timeout: timeoutMs });
  await client.connect();
  return client;
}

export async function check(cfg = {}, deps = {}) {
  const url = process.env.OPS_POSTGRES_DATABASE_URL;
  if (!url) {
    // Missing observability credential is UNKNOWN, NOT a Postgres outage.
    return { status: 'UNKNOWN', latencyMs: null, httpStatus: null, errorCode: 'NO_CREDENTIAL',
      details: { note: 'OPS_POSTGRES_DATABASE_URL not configured' } };
  }
  const timeoutMs = cfg.timeoutMs || DEFAULT_TIMEOUT_MS;
  const warnMs = cfg.degradedLatencyMs || DEFAULT_DEGRADED_LATENCY_MS;
  const connect = deps.connect || defaultConnect;
  const now = deps.now || (() => Date.now());

  let client = null;
  const t0 = now();
  try {
    client = await withTimeout(Promise.resolve(connect(url, timeoutMs)), timeoutMs, 'connect');
    await withTimeout(Promise.resolve(client.query('SELECT 1 AS ok')), timeoutMs, 'query');
    const latencyMs = now() - t0;
    if (latencyMs > warnMs) {
      return { status: 'DEGRADED', latencyMs, httpStatus: null, errorCode: 'SLOW', details: { note: 'SELECT 1 ok but slow' } };
    }
    return { status: 'HEALTHY', latencyMs, httpStatus: null, errorCode: null, details: { note: 'SELECT 1 ok' } };
  } catch (e) {
    const latencyMs = now() - t0;
    const errorCode = e && e.code === 'OPS_DRIVER' ? 'DRIVER_UNAVAILABLE' : classifyError(e);
    // DRIVER_UNAVAILABLE = ops not fully provisioned (secret set but `pg` not
    // installed) -> UNKNOWN, not a Postgres outage. All other errors = DOWN.
    const status = errorCode === 'DRIVER_UNAVAILABLE' ? 'UNKNOWN' : 'DOWN';
    return { status, latencyMs, httpStatus: null, errorCode, details: {} };
  } finally {
    if (client && typeof client.end === 'function') { try { await client.end(); } catch { /* ignore close error */ } }
  }
}
