// Feedback2Me — SAFE ON-DEMAND CANARIES. Read-only availability probes only. Every probe
// is a bounded GET with NO body — it never signs in, never writes, never generates a paid
// OpenAI request, never mutates. Endpoints are the product's own PUBLIC surfaces (verified
// from the repo). Runs only when explicitly invoked (button or `npm run ops:canary`) — never
// on the status-poll loop. Results are cached and fed to the health model as extra evidence.
import { CANARIES } from '../topology/health-map.js';
import { fileURLToPath, pathToFileURL } from 'node:url';

const TIMEOUT_MS = 6000;

async function probe(c, fetchImpl) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  const started = Date.now();
  try {
    // GET only, no body, no credentials, redirects followed but not required.
    const res = await fetchImpl(c.url, { method: 'GET', signal: controller.signal, redirect: 'follow' });
    clearTimeout(timer);
    const code = res.status;
    const latencyMs = Date.now() - started;
    let status, detail;
    if ((c.okStatuses || []).includes(code)) { status = 'HEALTHY'; detail = `reachable (HTTP ${code})`; }
    else if ((c.reachableStatuses || []).includes(code)) { status = 'HEALTHY'; detail = `reachable, access-guarded (HTTP ${code})`; }
    else if ((c.notDeployed || []).includes(code)) { status = 'N/A'; detail = `not deployed (HTTP ${code})`; }
    else if (code >= 500) { status = 'UNHEALTHY'; detail = `server error (HTTP ${code})`; }
    else { status = 'DEGRADED'; detail = `unexpected (HTTP ${code})`; }
    return { id: c.id, node: c.node, status, detail: `${detail} · ${latencyMs}ms`, httpStatus: code, latencyMs, desc: c.desc };
  } catch (e) {
    clearTimeout(timer);
    const to = e && e.name === 'AbortError';
    return { id: c.id, node: c.node, status: 'UNHEALTHY', detail: to ? `timeout > ${TIMEOUT_MS}ms` : 'network error', desc: c.desc };
  }
}

// Run every canary once (concurrently, bounded). Returns a map keyed by canary id +
// __runAt timestamp, safe to hand to the health model. Never throws.
export async function runCanaries({ fetchImpl = globalThis.fetch, now = Date.now() } = {}) {
  const results = {};
  await Promise.all(CANARIES.map(async (c) => { try { results[c.id] = await probe(c, fetchImpl); } catch { results[c.id] = { id: c.id, node: c.node, status: 'UNKNOWN', detail: 'probe failed', desc: c.desc }; } }));
  results.__runAt = new Date(now).toISOString();
  return results;
}

// CLI: `npm run ops:canary` — runs the probes once and prints the result table (no server).
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  runCanaries().then((r) => {
    console.log('[ops:canary] safe read-only availability probes:');
    for (const [id, v] of Object.entries(r)) { if (id.startsWith('__')) continue; console.log(`  ${String(v.status).padEnd(10)} ${id.padEnd(24)} ${v.detail || ''}`); }
    console.log('[ops:canary] ran at ' + r.__runAt);
  }).catch((e) => console.log('[ops:canary] failed: ' + e.message));
}
