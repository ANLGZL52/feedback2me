// Production-safe black-box check: HTTP GET reachability + latency. READ-ONLY.
export async function check(cfg) {
  const ctrl = new AbortController();
  const to = setTimeout(() => ctrl.abort(), cfg.timeoutMs || 8000);
  const t0 = Date.now();
  try {
    const res = await fetch(cfg.target, { method: 'GET', redirect: 'follow', signal: ctrl.signal, headers: { 'user-agent': 'feedback2me-ops/1' } });
    const latencyMs = Date.now() - t0;
    const ok = res.status >= 200 && res.status < 400;
    return { status: ok ? 'HEALTHY' : 'DOWN', latencyMs, httpStatus: res.status, errorCode: ok ? null : `HTTP_${res.status}`, details: {} };
  } catch (e) {
    const latencyMs = Date.now() - t0;
    const code = e.name === 'AbortError' ? 'TIMEOUT' : (e.cause && e.cause.code) || 'NETWORK';
    return { status: 'DOWN', latencyMs, httpStatus: null, errorCode: code, details: {} };
  } finally {
    clearTimeout(to);
  }
}
