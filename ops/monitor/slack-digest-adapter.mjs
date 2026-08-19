// Observability V7 — Slack Incoming Webhook adapter for the DAILY DIGEST only.
// This transport is for the once-per-day operational digest. It NEVER touches GitHub
// Issues / incident delivery (CRITICAL incidents stay on GitHub Issues). It NEVER logs
// or returns the webhook URL, request headers, or the HTTP body. Native fetch only —
// no new dependency. Bounded timeout + at most one conservative retry (429/5xx/timeout).
//
// adapter contract: { name, configured, async send(text, meta) -> {ok, status, latencyMs} }

const DEFAULT_TIMEOUT_MS = 8000;
const NO_RETRY = new Set([400, 401, 403, 404, 410, 422]);

/**
 * @param {string} webhookUrl  Slack incoming-webhook URL (from a GitHub Actions secret).
 *                             Empty/absent => configured:false => caller reports NOT_CONFIGURED.
 * @param {object} opts        { fetchImpl, timeoutMs, maxRetries, clock } (all injectable for tests)
 */
export function slackDigestAdapter(webhookUrl, { fetchImpl = globalThis.fetch, timeoutMs = DEFAULT_TIMEOUT_MS, maxRetries = 1, clock = () => Date.now() } = {}) {
  const configured = typeof webhookUrl === 'string' && webhookUrl.trim().length > 0;
  return {
    name: 'slack',
    configured,
    async send(text, meta = {}) {
      if (!configured) return { ok: false, status: null, latencyMs: 0, reason: 'not_configured' };
      const started = clock();
      const body = JSON.stringify({ text }); // Slack incoming-webhook shape: { "text": "..." }
      let attempt = 0, lastStatus = null;
      // one initial try + up to maxRetries retries, only for transient failures
      while (attempt <= maxRetries) {
        attempt++;
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), timeoutMs);
        try {
          const res = await fetchImpl(webhookUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body, signal: controller.signal });
          clearTimeout(timer);
          lastStatus = res.status;
          if (res.status >= 200 && res.status < 300) return { ok: true, status: res.status, latencyMs: clock() - started };
          if (NO_RETRY.has(res.status) || attempt > maxRetries) return { ok: false, status: res.status, latencyMs: clock() - started };
          // transient (429 / 5xx): honor a small Retry-After when present, then retry once.
          if (res.status === 429) { const ra = Number(res.headers && res.headers.get && res.headers.get('retry-after')); if (Number.isFinite(ra) && ra > 0 && ra <= 10) await sleep(ra * 1000); }
        } catch (e) {
          clearTimeout(timer);
          lastStatus = e && e.name === 'AbortError' ? 'timeout' : 'network_error';
          if (attempt > maxRetries) return { ok: false, status: lastStatus, latencyMs: clock() - started };
        }
      }
      return { ok: false, status: lastStatus, latencyMs: clock() - started };
    },
  };
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }
