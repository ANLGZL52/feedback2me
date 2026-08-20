// Feedback2Me — Ops Topology (zero-dependency interactive SVG). Reads the local read-only
// API and renders a living system map. No build step, no external libraries.
const SVGNS = 'http://www.w3.org/2000/svg';
const NODE_W = 162, NODE_H = 58;
const CAT_COLOR = {
  APPLICATION: '#58a6ff', DATA: '#a371f7', EXTERNAL_PROVIDER: '#e3b341', BACKEND: '#39c5cf',
  OBSERVABILITY: '#7ee787', SECURITY: '#ff7b72', INCIDENT: '#f85149', DELIVERY: '#db61a2', VALIDATION: '#f0883e',
};
const TAB_SUBSET = {
  map: null,
  runtime: ['collector', 'evaluator', 'railway', 'postgres', 'openai', 'wif', 'service_domain', 'security_domain', 'runtime_health'],
  incidents: ['evaluator', 'incident_engine', 'github_issues', 'security_domain', 'runtime_health'],
  iap: ['flutter_app', 'app_store', 'premium_product', 'iap_verify', 'apple_verification', 'processed_purchases', 'paid_link_credits', 'firestore', 'ai_summary'],
  release: ['runtime_health', 'evaluator', 'release_gate', 'real_iap_e2e'],
};
const IAP_INVARIANTS = ['IAP_SUCCESS_WITHOUT_CREDIT', 'IAP_GRANT_DELTA_NOT_ONE', 'IAP_REPLAY_DELTA_NOT_ZERO', 'IAP_CREDIT_UNKNOWN_PRODUCT', 'IAP_INVALID_PRODUCT_CREDITED', 'IAP_CREDIT_AFTER_FAILURE', 'IAP_DUPLICATE_GRANT'];

const S = { topo: null, pos: new Map(), view: { x: 40, y: 20, k: 0.72 }, sel: null, mode: 'none', trace: [], meta: null, statusById: new Map(), tab: 'map' };
const $ = (s) => document.querySelector(s);
const el = (n, a = {}) => { const e = document.createElementNS(SVGNS, n); for (const k in a) e.setAttribute(k, a[k]); return e; };
const api = (u) => fetch(u).then((r) => r.json());

// ---------- boot ----------
init().catch((e) => showBanner('Failed to load: ' + e.message));
async function init() {
  S.topo = await api('/api/topology');
  for (const n of S.topo.nodes) S.pos.set(n.id, { x: n.x, y: n.y });
  await refreshStatus();
  fitView();
  renderAll();
  wireGlobal();
  setInterval(refreshStatus, 30000); // poll status only; positions never move
}

// ---------- data ----------
async function refreshStatus() {
  try {
    const s = await api('/api/status');
    S.meta = s.meta; S.statusById = new Map(s.nodes.map((n) => [n.id, n]));
    renderStatusBar();
    updateNodeStatuses();
    $('#refreshed').textContent = 'Last refreshed: ' + new Date().toLocaleTimeString();
    if (!s.meta.present) showBanner('No ops-status artifact found locally — run `npm run ops:fetch` for live data. Showing structure with UNKNOWN status.');
    else hideBanner();
    if (S.tab !== 'map' && S.tab !== 'logs') renderInfoPanel();
  } catch (e) { showBanner('status refresh failed: ' + e.message); }
}

// ---------- status bar ----------
function renderStatusBar() {
  const m = S.meta || {};
  const item = (k, v, cls) => `<span class="sb"><span class="k">${k}</span>${cls ? pill(v, cls) : `<span class="v">${esc(v)}</span>`}</span>`;
  $('#statusbar').innerHTML =
    `<span class="brand">FEEDBACK2ME · OPS TOPOLOGY</span>` +
    item('env', m.environment || '—') +
    item('branch', m.branch || '—') +
    item('commit', (m.commit || '—')) +
    item('run', m.workflowRun || '—') +
    item('artifact', m.artifactTimestamp ? new Date(m.artifactTimestamp).toLocaleString() : '—') +
    item('runtime', m.runtime || 'UNKNOWN', sevOf(m.runtime)) +
    item('gate', m.gate || 'UNKNOWN', sevOf(m.gate)) +
    item('active critical', String(m.activeCritical ?? '—'), (m.activeCritical > 0 ? 'red' : 'green')) +
    item('collector', (m.collectorFreshnessMin != null ? m.collectorFreshnessMin + ' min' : 'N/A'));
}
function pill(v, cls) { return `<span class="pill ${cls}">${esc(v)}</span>`; }

// ---------- canvas render ----------
function renderAll() { renderCanvas(); renderLegend(); renderMinimap(); }
function renderCanvas() {
  const svg = $('#canvas'); svg.innerHTML = '';
  const vp = el('g', { id: 'viewport', transform: viewTransform() }); svg.appendChild(vp);
  S.gEdges = el('g'); S.gNodes = el('g'); vp.appendChild(S.gEdges); vp.appendChild(S.gNodes);
  renderEdges();
  const hi = highlightSet();
  for (const n of S.topo.nodes) S.gNodes.appendChild(nodeEl(n, hi));
}
// Edges are re-rendered on their own during drags (cheap; never re-attaches node handlers).
function renderEdges() {
  if (!S.gEdges) return; S.gEdges.innerHTML = '';
  const hi = highlightSet();
  const tracePairIds = new Set(S.tracePath ? S.tracePath.map((e) => e.id) : []);
  for (const e of S.topo.edges) {
    const a = center(e.source), b = center(e.target);
    const d = curve(a, b);
    const dim = (hi && !(hi.has(e.source) && hi.has(e.target))) || (S.tabSubset && !(S.tabSubset.has(e.source) && S.tabSubset.has(e.target)));
    const sev = (S.statusById.get(e.source) || {}).severity || e.severity;
    const cls = ['edge', sev, e.animated ? 'animated' : '', dim ? 'dim' : '', tracePairIds.has(e.id) ? 'trace' : ''].join(' ');
    S.gEdges.appendChild(el('path', { d, class: cls }));
    const hit = el('path', { d, class: 'edge-hit' }); hit.addEventListener('click', (ev) => { ev.stopPropagation(); openEdge(e); }); S.gEdges.appendChild(hit);
    const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
    if (!dim) { const t = el('text', { x: mx, y: my - 3, class: 'elabel', 'text-anchor': 'middle' }); t.textContent = e.type; S.gEdges.appendChild(t); }
  }
}
function nodeEl(n, hi) {
  const p = S.pos.get(n.id);
  const g = el('g', { class: 'node' + (S.sel === n.id ? ' sel' : ''), transform: `translate(${p.x},${p.y})`, 'data-id': n.id });
  const dim = (hi && !hi.has(n.id)) || (S.tabSubset && !S.tabSubset.has(n.id));
  if (dim) g.classList.add('dim');
  g.appendChild(el('rect', { class: 'box', width: NODE_W, height: NODE_H, rx: 10, ry: 10 }));
  g.appendChild(el('rect', { class: 'accent', x: 0, y: 0, width: 5, height: NODE_H, rx: 3, ry: 3, fill: CAT_COLOR[n.category] || '#888' }));
  const st = S.statusById.get(n.id) || { status: n.status, severity: n.severity };
  const dot = el('circle', { class: 'dot ' + (st.severity || 'grey'), cx: NODE_W - 16, cy: 16, r: 6 }); g.appendChild(dot);
  const cat = el('text', { class: 'cat', x: 14, y: 15 }); cat.textContent = n.category; g.appendChild(cat);
  const title = el('text', { class: 'title', x: 14, y: 32 }); title.textContent = n.label; g.appendChild(title);
  const role = el('text', { class: 'role', x: 14, y: 45 }); role.textContent = n.role; g.appendChild(role);
  const stt = el('text', { class: 'metric', x: 14, y: 55, 'data-status': 1 }); stt.textContent = statusLine(n, st); g.appendChild(stt);
  attachNodeInteract(g, n.id);
  return g;
}
function statusLine(n, st) { const m = (S.statusById.get(n.id) || {}).metric || n.metric; const mm = m && m.value !== 'N/A' && m.value != null ? ` · ${m.label} ${m.value}${m.unit || ''}` : ''; return `● ${st.status || '—'}${mm}`; }

function updateNodeStatuses() {
  for (const n of S.topo.nodes) {
    const g = document.querySelector(`.node[data-id="${cssq(n.id)}"]`); if (!g) continue;
    const st = S.statusById.get(n.id); if (!st) continue;
    const dot = g.querySelector('.dot'); if (dot) dot.setAttribute('class', 'dot ' + (st.severity || 'grey'));
    const stt = g.querySelector('[data-status]'); if (stt) stt.textContent = statusLine(n, st);
  }
  renderEdges(); // recolor edge paths by current source severity
}

// ---------- geometry ----------
function center(id) { const p = S.pos.get(id); return { x: p.x + NODE_W / 2, y: p.y + NODE_H / 2 }; }
function curve(a, b) { const dx = (b.x - a.x) * 0.3, dy = (b.y - a.y) * 0.5; return `M ${a.x} ${a.y} C ${a.x + dx} ${a.y + dy}, ${b.x - dx} ${b.y - dy}, ${b.x} ${b.y}`; }
function viewTransform() { return `translate(${S.view.x},${S.view.y}) scale(${S.view.k})`; }
function applyView() { const vp = $('#viewport'); if (vp) vp.setAttribute('transform', viewTransform()); drawMinimapViewport(); }
function bounds() { let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9; for (const p of S.pos.values()) { x0 = Math.min(x0, p.x); y0 = Math.min(y0, p.y); x1 = Math.max(x1, p.x + NODE_W); y1 = Math.max(y1, p.y + NODE_H); } return { x0, y0, x1, y1, w: x1 - x0, h: y1 - y0 }; }
function fitView() { const wrap = $('#canvas-wrap'); const b = bounds(); const k = Math.min((wrap.clientWidth - 60) / b.w, (wrap.clientHeight - 60) / b.h, 1); S.view.k = Math.max(0.3, k); S.view.x = (wrap.clientWidth - b.w * S.view.k) / 2 - b.x0 * S.view.k; S.view.y = 20 - b.y0 * S.view.k; }

// ---------- interactions ----------
// Node mousedown only sets drag intent; movement/commit is handled by the single global
// listeners in wireGlobal(), so no per-node window listeners accumulate across re-renders.
function attachNodeInteract(g, id) {
  g.addEventListener('mousedown', (ev) => { ev.stopPropagation(); const p = S.pos.get(id); S.drag = { id, g, mx: ev.clientX, my: ev.clientY, x: p.x, y: p.y, moved: false }; });
}
function wireGlobal() {
  const svg = $('#canvas'); let pan = null;
  svg.addEventListener('mousedown', (ev) => { pan = { mx: ev.clientX, my: ev.clientY, vx: S.view.x, vy: S.view.y }; svg.classList.add('grabbing'); });
  window.addEventListener('mousemove', (ev) => {
    if (S.drag) {
      const dx = (ev.clientX - S.drag.mx) / S.view.k, dy = (ev.clientY - S.drag.my) / S.view.k;
      if (Math.abs(dx) + Math.abs(dy) > 2) S.drag.moved = true;
      const nx = S.drag.x + dx, ny = S.drag.y + dy; S.pos.set(S.drag.id, { x: nx, y: ny });
      S.drag.g.setAttribute('transform', `translate(${nx},${ny})`); renderEdges();
      return;
    }
    if (pan) { S.view.x = pan.vx + (ev.clientX - pan.mx); S.view.y = pan.vy + (ev.clientY - pan.my); applyView(); }
  });
  window.addEventListener('mouseup', () => {
    if (S.drag) { if (!S.drag.moved) selectNode(S.drag.id); S.drag = null; }
    pan = null; svg.classList.remove('grabbing');
  });
  svg.addEventListener('click', () => { if (S.mode !== 'trace') { S.sel = null; closeDrawer(); clearHi(); } });
  svg.addEventListener('wheel', (ev) => { ev.preventDefault(); const r = svg.getBoundingClientRect(); const mx = ev.clientX - r.left, my = ev.clientY - r.top; const f = ev.deltaY < 0 ? 1.12 : 1 / 1.12; const nk = Math.max(0.25, Math.min(2.2, S.view.k * f)); S.view.x = mx - (mx - S.view.x) * (nk / S.view.k); S.view.y = my - (my - S.view.y) * (nk / S.view.k); S.view.k = nk; applyView(); }, { passive: false });

  document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => switchTab(t.dataset.tab)));
  $('#btn-deps').addEventListener('click', () => toggleMode('deps'));
  $('#btn-impact').addEventListener('click', () => toggleMode('impact'));
  $('#btn-trace').addEventListener('click', () => toggleMode('trace'));
  $('#btn-clear').addEventListener('click', clearAll);
  $('#btn-refresh').addEventListener('click', refreshStatus);
  $('#search').addEventListener('input', (e) => onSearch(e.target.value));
  $('#search').addEventListener('keydown', (e) => { if (e.key === 'Enter') { const first = matchNodes(e.target.value)[0]; if (first) centerNode(first.id); } });
  window.addEventListener('resize', () => { renderMinimap(); });
}
function toggleMode(mode) {
  if (S.mode === mode) { clearAll(); return; }
  S.mode = mode; S.trace = []; S.tracePath = null;
  ['deps', 'impact', 'trace'].forEach((m) => $('#btn-' + m).classList.toggle('on', m === mode));
  $('#trace-hint').textContent = mode === 'trace' ? 'TRACE: click a source node, then a target node.' : (S.sel ? '' : 'Select a node to ' + (mode === 'deps' ? 'show dependencies.' : 'show failure impact.'));
  renderCanvas();
}
function clearAll() { S.mode = 'none'; S.trace = []; S.tracePath = null; ['deps', 'impact', 'trace'].forEach((m) => $('#btn-' + m).classList.remove('on')); $('#trace-hint').textContent = ''; renderCanvas(); }
function clearHi() { if (S.mode !== 'trace') { S.mode = 'none'; ['deps', 'impact', 'trace'].forEach((m) => $('#btn-' + m).classList.remove('on')); renderCanvas(); } }

// ---------- highlight logic ----------
function outAdj(id) { return S.topo.edges.filter((e) => e.source === id).map((e) => e.target); }
function inAdj(id) { return S.topo.edges.filter((e) => e.target === id).map((e) => e.source); }
function closure(id, adj) { const seen = new Set(); const q = [id]; while (q.length) { const c = q.shift(); for (const t of adj(c)) if (!seen.has(t)) { seen.add(t); q.push(t); } } seen.delete(id); return seen; }
function highlightSet() {
  if (S.mode === 'trace' && S.tracePath) { const s = new Set(); for (const e of S.tracePath) { s.add(e.source); s.add(e.target); } return s; }
  if (!S.sel) return null;
  if (S.mode === 'deps') { const up = closure(S.sel, inAdj), down = closure(S.sel, outAdj); return new Set([S.sel, ...up, ...down]); }
  if (S.mode === 'impact') { const down = closure(S.sel, outAdj); return new Set([S.sel, ...down]); }
  return null;
}

// ---------- selection + drawer ----------
async function selectNode(id) {
  if (S.mode === 'trace') { handleTracePick(id); return; }
  S.sel = id; renderCanvas();
  const d = await api('/api/node/' + encodeURIComponent(id));
  openDrawer(d);
}
function centerNode(id) { const p = S.pos.get(id); const wrap = $('#canvas-wrap'); S.view.k = Math.max(S.view.k, 0.8); S.view.x = wrap.clientWidth / 2 - (p.x + NODE_W / 2) * S.view.k; S.view.y = wrap.clientHeight / 2 - (p.y + NODE_H / 2) * S.view.k; applyView(); selectNode(id); }

function openDrawer(d) {
  const dr = $('#drawer'); dr.classList.add('open');
  const list = (arr) => arr && arr.length ? `<div class="chiprow">${arr.map((x) => `<span class="chip" data-goto="${esc(x.id)}">${esc(x.label)}</span>`).join('')}</div>` : '<span class="hint">none</span>';
  const codes = (arr) => arr && arr.length ? `<div class="chiprow">${arr.map((c) => `<span class="chip code">${esc(c)}</span>`).join('')}</div>` : '<span class="hint">none</span>';
  const rbs = (arr) => arr && arr.length ? `<div class="chiprow">${arr.map((c) => `<span class="chip rb">${esc(c)}</span>`).join('')}</div>` : '<span class="hint">none</span>';
  const srcs = (arr) => arr && arr.length ? `<div class="chiprow">${arr.map((c) => `<span class="chip src">${esc(c)}</span>`).join('')}</div>` : '<span class="hint">none</span>';
  const ev = (d.recentEvents || []).slice(0, 25).map((e) => `<div class="evrow"><span class="sev ${e.severity}">${e.severity[0]}</span><span>${esc(e.event)}</span><span class="hint">${e.time ? new Date(e.time).toLocaleTimeString() : ''}</span></div>`).join('') || '<span class="hint">no recent events for this domain</span>';
  dr.innerHTML = `<div class="d-inner">
    <button class="close" data-close>×</button>
    <h2>${esc(d.label)} ${pill(d.status, d.severity)}</h2>
    <div class="sub">${esc(d.category)} · ${esc(d.role)}</div>
    <div class="desc">${esc(d.description)}</div>
    ${d.metric ? `<section><h4>Key metric</h4>${esc(d.metric.label)}: <b>${esc(String(d.metric.value))}${esc(d.metric.unit || '')}</b></section>` : ''}
    <section><h4>Depends on</h4>${list(d.dependsOn)}</section>
    <section><h4>Used by</h4>${list(d.usedBy)}</section>
    <section><h4>Observed by</h4>${list(d.observedBy)}</section>
    <section><h4>Downstream impact if it fails</h4>${list(d.downstreamImpact)}</section>
    <section><h4>Alert codes</h4>${codes(d.alertCodes)}</section>
    <section><h4>Runbook sections</h4>${rbs(d.runbook)}</section>
    <section><h4>Source files</h4>${srcs(d.sources)}</section>
    <section><h4>Recent operational events</h4>${ev}</section>
    <section><h4>Last update</h4><span class="hint">${d.lastUpdate ? new Date(d.lastUpdate).toLocaleString() : '—'}</span></section>
  </div>`;
  dr.querySelector('[data-close]').addEventListener('click', () => { S.sel = null; closeDrawer(); clearHi(); });
  dr.querySelectorAll('[data-goto]').forEach((c) => c.addEventListener('click', () => centerNode(c.dataset.goto)));
}
function openEdge(e) {
  const dr = $('#drawer'); dr.classList.add('open'); S.sel = null; renderCanvas();
  const nm = (id) => { const n = S.topo.nodes.find((x) => x.id === id); return n ? n.label : id; };
  const row = (k, v) => v ? `<section><h4>${k}</h4><div class="desc">${esc(v)}</div></section>` : '';
  dr.innerHTML = `<div class="d-inner">
    <button class="close" data-close>×</button>
    <h2>${esc(nm(e.source))} → ${esc(nm(e.target))}</h2>
    <div class="sub">RELATION · ${esc(e.type)}</div>
    ${row('Purpose', e.purpose)}
    ${row('Input', e.input)}
    ${row('Output', e.output)}
    ${row('Security boundary', e.security)}
    ${row('Failure behavior', e.failure)}
    ${row('Observability coverage', e.observability)}
  </div>`;
  dr.querySelector('[data-close]').addEventListener('click', () => closeDrawer());
}
function closeDrawer() { $('#drawer').classList.remove('open'); }

// ---------- trace ----------
function handleTracePick(id) {
  S.trace.push(id);
  if (S.trace.length === 1) { $('#trace-hint').textContent = `TRACE: from ${label(id)} → click target…`; S.sel = id; renderCanvas(); return; }
  const [from, to] = S.trace; S.trace = [];
  const path = clientPath(from, to);
  S.tracePath = path;
  $('#trace-hint').textContent = path.length ? `PATH ${label(from)} → ${label(to)} (${path.length} hops)` : `No directed path ${label(from)} → ${label(to)}`;
  renderCanvas();
}
function clientPath(from, to) { if (from === to) return []; const prev = new Map(); const q = [from]; const seen = new Set([from]); while (q.length) { const c = q.shift(); for (const e of S.topo.edges) if (e.source === c && !seen.has(e.target)) { seen.add(e.target); prev.set(e.target, e); if (e.target === to) { const p = []; let cur = to; while (prev.has(cur)) { const ed = prev.get(cur); p.unshift(ed); cur = ed.source; } return p; } q.push(e.target); } } return []; }

// ---------- search ----------
function matchNodes(q) { q = (q || '').trim().toLowerCase(); if (!q) return []; return S.topo.nodes.filter((n) => n.label.toLowerCase().includes(q) || n.id.includes(q) || n.category.toLowerCase().includes(q)); }
function onSearch(q) { const set = new Set(matchNodes(q).map((n) => n.id)); document.querySelectorAll('.node').forEach((g) => { const id = g.dataset.id; g.classList.toggle('dim', q && !set.has(id)); }); }

// ---------- tabs ----------
function switchTab(tab) {
  S.tab = tab; document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === tab));
  const wrap = $('#canvas-wrap');
  if (tab === 'logs') { wrap.classList.add('hidden'); showLogs(); return; }
  wrap.classList.remove('hidden'); removeLogs();
  S.tabSubset = TAB_SUBSET[tab] ? new Set(TAB_SUBSET[tab]) : null;
  renderCanvas();
  if (tab === 'map') { $('#panel').classList.add('hidden'); } else { renderInfoPanel(); }
}
function renderInfoPanel() {
  const p = $('#panel'); p.classList.remove('hidden'); const m = S.meta || {}; const stat = (id) => (S.statusById.get(id) || {}).status || '—';
  const kv = (k, v, cls) => `<div class="kv"><span class="k">${k}</span>${cls ? pill(v, cls) : `<span>${esc(v)}</span>`}</div>`;
  if (S.tab === 'runtime') p.innerHTML = `<h3>RUNTIME</h3>${kv('Collector', stat('collector'), sevOf(stat('collector')))}${kv('Railway', stat('railway'), sevOf(stat('railway')))}${kv('Postgres', stat('postgres'), sevOf(stat('postgres')))}${kv('OpenAI', stat('openai'), sevOf(stat('openai')))}${kv('Security', stat('security_domain'), sevOf(stat('security_domain')))}${kv('Service', stat('service_domain'), sevOf(stat('service_domain')))}${kv('Collector freshness', (m.collectorFreshnessMin != null ? m.collectorFreshnessMin + ' min' : 'N/A'))}`;
  else if (S.tab === 'incidents') p.innerHTML = `<h3>INCIDENT PIPELINE</h3>${kv('Delivery mode', m.incidentMode || '—', sevOf(m.incidentMode))}${kv('Active critical', String(m.activeCritical ?? '—'), (m.activeCritical > 0 ? 'red' : 'green'))}${kv('Canonical writer', 'ONE', 'green')}${kv('Legacy writer', 'OFF', 'green')}${kv('Slack for incidents', 'NO', 'green')}<div class="kv"><span class="k">Path</span><span>Evaluator → Incident Engine → GitHub Issues</span></div>`;
  else if (S.tab === 'iap') p.innerHTML = `<h3>IAP MONEY-SAFETY</h3>${IAP_INVARIANTS.map((c) => { const bad = stat('iap_verify') === 'UNHEALTHY'; return `<div class="kv"><span class="k" style="font-size:11px">${c}</span>${pill(bad ? 'CHECK' : 'OK', bad ? 'red' : 'green')}</div>`; }).join('')}${kv('IAP domain', stat('iap_verify'), sevOf(stat('iap_verify')))}${kv('Real IAP TestFlight E2E', m.realIapE2E || 'DEFERRED', 'amber')}`;
  else if (S.tab === 'release') p.innerHTML = `<h3>RELEASE CHAIN</h3>${kv('Observability Platform', m.observabilityPlatform || '—', sevOf(m.observabilityPlatform))}${kv('Runtime Validation', m.runtimeValidation || '—', sevOf(m.runtimeValidation))}${kv('Real IAP E2E', m.realIapE2E || 'DEFERRED', 'amber')}${kv('Product Release Gate', m.gate || '—', sevOf(m.gate))}<div class="kv"><span class="k">Chain</span><span>Platform → Validation → Gate</span></div>`;
}

// ---------- logs ----------
let logState = { domain: 'ALL', severity: 'ALL' };
async function showLogs() {
  let host = $('#logs'); if (!host) { host = document.createElement('div'); host.id = 'logs'; host.className = 'logs'; $('.stage').insertBefore(host, $('#drawer')); }
  const doms = ['ALL', 'IAP', 'OPENAI', 'RAILWAY', 'POSTGRES', 'COLLECTOR', 'INCIDENT', 'SLACK', 'SECURITY'];
  const sevs = ['ALL', 'INFO', 'WARNING', 'CRITICAL'];
  host.innerHTML = `<div class="filters">${doms.map((d) => `<button class="fbtn ${logState.domain === d ? 'on' : ''}" data-dom="${d}">${d}</button>`).join('')}<span style="width:14px"></span>${sevs.map((s) => `<button class="fbtn ${logState.severity === s ? 'on' : ''}" data-sev="${s}">${s}</button>`).join('')}</div>
    <table><thead><tr><th>Time</th><th>Domain</th><th>Event</th><th>Severity</th><th>Status</th><th>Source</th></tr></thead><tbody id="logbody"><tr><td colspan="6" class="hint">loading…</td></tr></tbody></table>`;
  host.querySelectorAll('[data-dom]').forEach((b) => b.addEventListener('click', () => { logState.domain = b.dataset.dom; showLogs(); }));
  host.querySelectorAll('[data-sev]').forEach((b) => b.addEventListener('click', () => { logState.severity = b.dataset.sev; showLogs(); }));
  const r = await api(`/api/events?domain=${logState.domain}&severity=${logState.severity}`);
  const body = $('#logbody');
  if (!r.events || !r.events.length) { body.innerHTML = `<tr><td colspan="6" class="hint">${r.present ? 'no matching events' : 'no artifact — run npm run ops:fetch'}</td></tr>`; return; }
  body.innerHTML = r.events.map((e) => `<tr data-dom="${esc(e.domain)}"><td class="hint">${e.time ? new Date(e.time).toLocaleTimeString() : '—'}</td><td>${esc(e.domain)}</td><td>${esc(e.event)}</td><td class="sev ${e.severity}">${e.severity}</td><td>${esc(e.status || '')}</td><td class="hint">${esc(e.source || '')}</td></tr>`).join('');
}
function removeLogs() { const h = $('#logs'); if (h) h.remove(); }

// ---------- legend + minimap ----------
function renderLegend() {
  const sw = (c, t) => `<div class="row"><span class="sw" style="background:${c}"></span>${t}</div>`;
  $('#legend').innerHTML = `<div class="row"><b>status</b></div>${sw('#2ea043', 'healthy / live / full')}${sw('#d29922', 'warn / partial / idle / deferred')}${sw('#f85149', 'critical / block / unhealthy')}${sw('#6e7681', 'unknown / not configured')}<div class="row" style="margin-top:4px"><b>scroll</b> zoom · <b>drag</b> pan/move</div>`;
}
function renderMinimap() {
  const mm = $('#minimap'); mm.innerHTML = ''; const b = bounds(); const pad = 10; const kw = (210 - pad * 2) / b.w, kh = (150 - pad * 2) / b.h; const k = Math.min(kw, kh); mm.dataset.k = k; mm.dataset.x0 = b.x0; mm.dataset.y0 = b.y0; mm.dataset.pad = pad;
  const g = el('g', { transform: `translate(${pad - b.x0 * k},${pad - b.y0 * k}) scale(${k})` }); mm.appendChild(g);
  for (const e of S.topo.edges) { const a = center(e.source), c = center(e.target); g.appendChild(el('line', { x1: a.x, y1: a.y, x2: c.x, y2: c.y, stroke: '#30363d', 'stroke-width': 1 })); }
  for (const n of S.topo.nodes) { const p = S.pos.get(n.id); const st = S.statusById.get(n.id) || {}; g.appendChild(el('rect', { x: p.x, y: p.y, width: NODE_W, height: NODE_H, rx: 6, fill: colorFor(st.severity || n.severity) })); }
  mm.appendChild(el('rect', { id: 'mmview', fill: 'none', stroke: '#58a6ff', 'stroke-width': 2 }));
  drawMinimapViewport();
}
function drawMinimapViewport() {
  const mm = $('#minimap'); const rect = mm && mm.querySelector('#mmview'); if (!rect) return; const wrap = $('#canvas-wrap'); const k = +mm.dataset.k, x0 = +mm.dataset.x0, y0 = +mm.dataset.y0, pad = +mm.dataset.pad;
  const vx = (-S.view.x / S.view.k), vy = (-S.view.y / S.view.k), vw = wrap.clientWidth / S.view.k, vh = wrap.clientHeight / S.view.k;
  rect.setAttribute('x', pad + (vx - x0) * k); rect.setAttribute('y', pad + (vy - y0) * k); rect.setAttribute('width', Math.max(4, vw * k)); rect.setAttribute('height', Math.max(4, vh * k));
}

// ---------- utils ----------
function sevOf(v) { const s = (v || '').toString().toUpperCase(); if (['HEALTHY', 'FULL', 'LIVE', 'VERIFIED', 'PASS', 'OK'].includes(s)) return 'green'; if (['WARN', 'PARTIAL', 'DEFERRED', 'IDLE', 'DEGRADED'].includes(s)) return 'amber'; if (['CRITICAL', 'BLOCK', 'UNHEALTHY', 'DOWN', 'FAILED', 'UNAVAILABLE'].includes(s)) return 'red'; return 'grey'; }
function colorFor(sev) { return { green: '#2ea043', amber: '#d29922', red: '#f85149', grey: '#6e7681' }[sev] || '#6e7681'; }
function label(id) { const n = S.topo.nodes.find((x) => x.id === id); return n ? n.label : id; }
function esc(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
function cssq(s) { return String(s).replace(/"/g, '\\"'); }
function showBanner(t) { const b = $('#banner'); b.textContent = t; b.classList.remove('hidden'); }
function hideBanner() { $('#banner').classList.add('hidden'); }
