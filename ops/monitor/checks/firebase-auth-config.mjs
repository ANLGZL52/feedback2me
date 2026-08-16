// Production-safe READ-ONLY Firebase Auth SERVICE health check.
// Calls identitytoolkit getProjectConfig with the PUBLIC web API key (already
// public in web_static/f.html). A 200 proves the Identity Platform service is
// reachable and the project's auth config exists. It does NOT attempt any sign-in
// and does NOT verify the real owner Google/Apple JOURNEY (that stays synthetic /
// NOT VERIFIED). No account is created, no user data is touched, no secret is used.
const PUBLIC_WEB_API_KEY = process.env.FIREBASE_WEB_API_KEY || 'AIzaSyCRflC9vEs78jUte24z4mzGU2AXtaVKV_M';
const URL = 'https://www.googleapis.com/identitytoolkit/v3/relyingparty/getProjectConfig';

export async function check(cfg) {
  const ctrl = new AbortController();
  const to = setTimeout(() => ctrl.abort(), (cfg && cfg.timeoutMs) || 8000);
  const t0 = Date.now();
  try {
    const res = await fetch(`${URL}?key=${PUBLIC_WEB_API_KEY}`, { method: 'GET', signal: ctrl.signal });
    const latencyMs = Date.now() - t0;
    if (res.status === 200) {
      let n = null;
      try { const b = await res.json(); n = Array.isArray(b.authorizedDomains) ? b.authorizedDomains.length : null; } catch {}
      return { status: 'HEALTHY', latencyMs, httpStatus: 200, errorCode: null,
        details: { note: 'identitytoolkit reachable' + (n != null ? ` (${n} authorized domains)` : '') } };
    }
    if (res.status === 403 || res.status === 400) {
      // service reachable but the API key/config was rejected — config/health signal, not an outage
      return { status: 'DEGRADED', latencyMs, httpStatus: res.status, errorCode: 'AUTH_CONFIG_REJECTED', details: {} };
    }
    return { status: 'DOWN', latencyMs, httpStatus: res.status, errorCode: `HTTP_${res.status}`, details: {} };
  } catch (e) {
    const latencyMs = Date.now() - t0;
    return { status: 'DOWN', latencyMs, httpStatus: null, errorCode: e.name === 'AbortError' ? 'TIMEOUT' : 'NETWORK', details: {} };
  } finally {
    clearTimeout(to);
  }
}
