// Production-safe black-box check: READ-ONLY public read of appConfig/version via
// Firestore REST + the PUBLIC web apiKey (already public in web_static/f.html).
// Proves Firestore reachable + rules allow public appConfig read; surfaces
// minSupportedBuild/latestBuild. Touches NO user data. No secrets.
const PUBLIC_WEB_API_KEY = process.env.FIREBASE_WEB_API_KEY || 'AIzaSyCRflC9vEs78jUte24z4mzGU2AXtaVKV_M';

export async function check(cfg) {
  const url = `${cfg.target}?key=${PUBLIC_WEB_API_KEY}`;
  const ctrl = new AbortController();
  const to = setTimeout(() => ctrl.abort(), cfg.timeoutMs || 8000);
  const t0 = Date.now();
  try {
    const res = await fetch(url, { method: 'GET', signal: ctrl.signal });
    const latencyMs = Date.now() - t0;
    // reachabilityOnly: any HTTP response proves the service is reachable (used
    // for node-firestore reachability, independent of the specific rule).
    if (cfg.reachabilityOnly) {
      return { status: 'HEALTHY', latencyMs, httpStatus: res.status, errorCode: null, details: { note: 'reachable (http ' + res.status + ')' } };
    }
    if (res.status === 404) {
      // Firestore reachable + rule allowed the read, but the doc doesn't exist yet.
      return { status: 'HEALTHY', latencyMs, httpStatus: 404, errorCode: 'APPCONFIG_MISSING', details: { note: 'appConfig/version not created yet (Phase 4 of migration)' } };
    }
    if (res.status === 403) {
      return { status: 'DEGRADED', latencyMs, httpStatus: 403, errorCode: 'RULES_DENY', details: { note: 'appConfig public read denied — rules drift?' } };
    }
    if (res.status < 200 || res.status >= 300) {
      return { status: 'DOWN', latencyMs, httpStatus: res.status, errorCode: `HTTP_${res.status}`, details: {} };
    }
    const body = await res.json();
    const f = (body && body.fields) || {};
    const minSupportedBuild = f.minSupportedBuild ? Number(f.minSupportedBuild.integerValue ?? f.minSupportedBuild.doubleValue) : null;
    const latestBuild = f.latestBuild ? Number(f.latestBuild.integerValue ?? f.latestBuild.doubleValue) : null;
    return { status: 'HEALTHY', latencyMs, httpStatus: 200, errorCode: null, details: { minSupportedBuild, latestBuild } };
  } catch (e) {
    const latencyMs = Date.now() - t0;
    const code = e.name === 'AbortError' ? 'TIMEOUT' : (e.cause && e.cause.code) || 'NETWORK';
    return { status: 'DOWN', latencyMs, httpStatus: null, errorCode: code, details: {} };
  } finally {
    clearTimeout(to);
  }
}
