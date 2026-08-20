// Read-only topology dashboard — local HTTP server. Binds to 127.0.0.1 ONLY. No external
// network, no production writes. Serves a normalized read-only API + the static UI.
// Run: node server/server.mjs   (or: npm run ops:topology)
import { createServer } from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, extname, normalize } from 'node:path';
import { readArtifacts } from './artifact-reader.mjs';
import { buildTopology, buildMeta, buildNodeDetail } from './topology-model.mjs';
import { buildSystem, resolveNode } from './health-model.mjs';
import { runCanaries } from './canary.mjs';

// In-memory cache of the last on-demand canary run (never auto-run on the poll loop).
let canaryCache = {};

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');            // ops/topology-dashboard
const PUBLIC = join(ROOT, 'public');
const HOST = '127.0.0.1';
const PORT = Number(process.env.OPS_TOPOLOGY_PORT || 4173);

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8', '.svg': 'image/svg+xml' };

const json = (res, code, body) => {
  const s = JSON.stringify(body);
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
  res.end(s);
};

function serveStatic(res, urlPath) {
  // map / -> index.html; allow /public/* , /topology/* (topology modules shared with browser)
  let rel = urlPath === '/' ? 'public/index.html' : urlPath.replace(/^\/+/, '');
  if (rel.startsWith('topology/')) rel = rel; // served from ROOT
  else if (!rel.startsWith('public/')) rel = join('public', rel);
  const full = normalize(join(ROOT, rel));
  if (!full.startsWith(ROOT)) { res.writeHead(403); return res.end('forbidden'); } // no traversal
  if (!existsSync(full)) { res.writeHead(404); return res.end('not found'); }
  const type = MIME[extname(full)] || 'application/octet-stream';
  res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  res.end(readFileSync(full));
}

const server = createServer((req, res) => {
  const url = new URL(req.url, `http://${HOST}:${PORT}`);
  const p = url.pathname;
  try {
    if (p === '/api/health') return json(res, 200, { ok: true, service: 'ops-topology', ts: nowIso() });
    if (p === '/api/topology') { const art = readArtifacts(); return json(res, 200, buildTopology(art)); }
    if (p === '/api/status') {
      const art = readArtifacts();
      const nodes = buildTopology(art).nodes.map((n) => { const h = resolveNode(n.id, art, canaryCache); return { id: n.id, status: n.status, severity: n.severity, metric: n.metric, serviceHealth: h.serviceHealth, serviceSeverity: h.severity, trafficState: h.trafficState, business: h.business, observable: h.observable, probe: h.probe }; });
      return json(res, 200, { meta: buildMeta(art), system: buildSystem(art, canaryCache), nodes });
    }
    if (p === '/api/system') { const art = readArtifacts(); return json(res, 200, buildSystem(art, canaryCache)); }
    if (p === '/api/canary') { // on-demand: run the safe read-only canaries once, cache, return system
      const art = readArtifacts();
      return runCanaries().then((r) => { canaryCache = r; return json(res, 200, { ran: true, system: buildSystem(art, canaryCache) }); }).catch((e) => json(res, 200, { ran: false, error: String(e && e.message || e), system: buildSystem(art, canaryCache) }));
    }
    if (p === '/api/events') {
      const art = readArtifacts();
      const dm = (url.searchParams.get('domain') || 'ALL').toUpperCase();
      const sv = (url.searchParams.get('severity') || 'ALL').toUpperCase();
      let ev = art.events;
      if (dm !== 'ALL') ev = ev.filter((e) => e.domain === dm);
      if (sv !== 'ALL') ev = ev.filter((e) => e.severity === sv);
      return json(res, 200, { events: ev.slice(0, 300), present: art.present });
    }
    if (p.startsWith('/api/node/')) {
      const id = decodeURIComponent(p.slice('/api/node/'.length));
      const art = readArtifacts();
      const detail = buildNodeDetail(id, art);
      if (!detail) return json(res, 404, { error: 'unknown node' });
      const h = resolveNode(id, art, canaryCache);
      return json(res, 200, { ...detail, health: h });
    }
    if (p.startsWith('/api/')) return json(res, 404, { error: 'unknown endpoint' });
    return serveStatic(res, p);
  } catch (e) {
    return json(res, 500, { error: 'internal', message: String(e && e.message || e) });
  }
});

function nowIso() { try { return new Date().toISOString(); } catch { return null; } }

server.listen(PORT, HOST, () => {
  const art = readArtifacts();
  const meta = buildMeta(art);
  // eslint-disable-next-line no-console
  console.log(`[ops-topology] read-only dashboard on http://${HOST}:${PORT}`);
  console.log(`[ops-topology] artifact present: ${art.present ? 'YES' : 'NO (run: npm run ops:fetch)'}  runtime=${meta.runtime} gate=${meta.gate} activeCritical=${meta.activeCritical} commit=${meta.commit || '—'}`);
});
