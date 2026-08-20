// Feedback2Me Control Center — zero-dependency interactive SVG topology. Reads the local
// read-only API. No build, no external libraries. UI refinement over the original graph:
// swimlane groups, larger nodes, focus mode, edge chips, camera controls, fullscreen.
const SVGNS = 'http://www.w3.org/2000/svg';
const LABEL_ZOOM = 0.5; // hide edge labels below this zoom
const CAT_COLOR = {
  APPLICATION: '#58a6ff', DATA: '#a371f7', EXTERNAL_PROVIDER: '#e3b341', BACKEND: '#39c5cf',
  OBSERVABILITY: '#7ee787', SECURITY: '#ff7b72', INCIDENT: '#f85149', DELIVERY: '#db61a2', VALIDATION: '#f0883e',
};
const CAT_LABELS = ['APPLICATION', 'DATA', 'EXTERNAL_PROVIDER', 'BACKEND', 'OBSERVABILITY', 'SECURITY', 'INCIDENT', 'DELIVERY', 'VALIDATION'];
const EDGE_TYPES = ['AUTH', 'DATA_FLOW', 'OBSERVES', 'VERIFIES', 'PERSISTS', 'EVALUATES', 'TRIGGERS', 'DELIVERS', 'DEPENDS_ON', 'SECURES', 'VALIDATION'];
const TAB_SUBSET = {
  map: null,
  runtime: ['collector', 'evaluator', 'railway', 'postgres', 'openai', 'wif', 'service_domain', 'security_domain', 'runtime_health'],
  incidents: ['evaluator', 'incident_engine', 'github_issues', 'security_domain', 'runtime_health'],
  iap: ['flutter_app', 'app_store', 'premium_product', 'iap_verify', 'apple_verification', 'processed_purchases', 'paid_link_credits', 'firestore', 'ai_summary', 'real_iap_e2e'],
  release: ['runtime_health', 'evaluator', 'release_gate', 'real_iap_e2e'],
};
const IAP_INVARIANTS = ['IAP_SUCCESS_WITHOUT_CREDIT', 'IAP_GRANT_DELTA_NOT_ONE', 'IAP_REPLAY_DELTA_NOT_ZERO', 'IAP_CREDIT_UNKNOWN_PRODUCT', 'IAP_INVALID_PRODUCT_CREDITED', 'IAP_CREDIT_AFTER_FAILURE', 'IAP_DUPLICATE_GRANT'];

const S = { topo: null, pos: new Map(), view: { x: 40, y: 20, k: 0.62 }, sel: null, mode: 'none', trace: [], tracePath: null, meta: null, statusById: new Map(), tab: 'map', tabSubset: null, drag: null, drawerClosed: {} };
const $ = (s) => document.querySelector(s);
const el = (n, a = {}) => { const e = document.createElementNS(SVGNS, n); for (const k in a) e.setAttribute(k, a[k]); return e; };
const api = (u) => fetch(u).then((r) => r.json());
const NW = (n) => n.w || 216, NH = (n) => n.h || 86;

init().catch((e) => showBanner('Failed to load: ' + e.message));
async function init() {
  S.topo = await api('/api/topology');
  for (const n of S.topo.nodes) S.pos.set(n.id, { x: n.x, y: n.y });
  await refreshStatus();
  resetView();
  renderAll();
  wireGlobal();
  setInterval(refreshStatus, 30000);
}

// ---------- data / status ----------
async function refreshStatus() {
  try {
    const s = await api('/api/status');
    S.meta = s.meta; S.system = s.system; S.statusById = new Map(s.nodes.map((n) => [n.id, n]));
    renderStatusBar(); renderSysHealth(); updateNodeStatuses();
    $('#refreshed').textContent = 'refreshed ' + new Date().toLocaleTimeString();
    if (!s.meta.present) showBanner('No ops-status artifact found locally — run `npm run ops:fetch` for live data. Showing structure with UNKNOWN status.'); else hideBanner();
    if (S.tab !== 'map' && S.tab !== 'logs') renderInfoPanel();
  } catch (e) { showBanner('status refresh failed: ' + e.message); }
}
function renderStatusBar() {
  const m = S.meta || {};
  const col = (k, v, cls) => `<div class="sb"><span class="k">${k}</span>${cls ? pill(v, cls) : `<span class="v">${esc(v)}</span>`}</div>`;
  $('#statusbar').innerHTML =
    `<div class="brand"><span class="dot" style="background:${colorFor(sevOf(m.runtime))};box-shadow:0 0 8px ${colorFor(sevOf(m.runtime))}"></span>Feedback2Me Control Center</div>` +
    col('Runtime', m.runtime || 'UNKNOWN', sevOf(m.runtime)) +
    col('Observability', m.observabilityPlatform || 'UNKNOWN', sevOf(m.observabilityPlatform)) +
    col('Release Gate', m.gate || 'UNKNOWN', sevOf(m.gate)) +
    col('Critical', String(m.activeCritical ?? '—'), (m.activeCritical > 0 ? 'red' : 'green')) +
    col('Slack', m.digestChannel === 'slack' ? (m.digestHealth === 'NOT_CONFIGURED' ? 'NOT_CONFIGURED' : 'LIVE') : 'UNKNOWN', sevOf(m.digestChannel === 'slack' && m.digestHealth !== 'NOT_CONFIGURED' ? 'LIVE' : 'UNKNOWN')) +
    col('Collector', (m.collectorFreshnessMin != null ? m.collectorFreshnessMin + ' min' : 'N/A')) +
    col('Branch / Commit', (m.branch || '—') + ' · ' + (m.commit || '—')) +
    col('Last refresh', m.artifactTimestamp ? new Date(m.artifactTimestamp).toLocaleTimeString() : '—');
}

// ---------- system health strip ----------
function renderSysHealth() {
  const sys = S.system; const host = $('#syshealth'); if (!sys) { host.innerHTML = ''; return; }
  const ov = sevOf(sys.overall);
  const paths = (sys.paths || []).map((p) => `<div class="pathchip" data-path="${esc(p.weakest || '')}" title="${esc(p.gaps && p.gaps.length ? 'coverage gaps: ' + p.gaps.join(', ') : '')}"><span class="pn">${esc(p.name.toUpperCase())}</span><span class="ps ${sevOf(p.status)}">${esc(p.status)}</span></div>`).join('');
  const cov = sys.coverage || {};
  const why = (sys.overall !== 'HEALTHY' && (sys.reasons || []).length)
    ? `<div class="syswhy ${ov}"><span class="wtag">WHY?</span>${sys.reasons.map((r) => `<span>${esc(r.label)} <b>${esc(r.status)}</b>${r.alert ? ' · ' + esc(r.alert) : ''}${r.incident && r.incident.issueNumber ? ' · incident #' + r.incident.issueNumber : ''}${r.paths && r.paths.length ? ' · affects ' + esc(r.paths.join(', ')) : ''} <span class="wnode" data-goto="${esc(r.node)}">inspect</span></span>`).join('')}</div>` : '';
  host.innerHTML = `
    <div class="sysoverall ${ov}"><span class="bulb" style="background:${colorFor(ov)};box-shadow:0 0 10px ${colorFor(ov)}"></span><div><div class="lab">Overall System Health</div><div class="big">${esc(sys.overall)}</div></div></div>
    <div class="syspaths">${paths}</div>
    <div class="syscov">
      <div class="covitem"><span class="cn">Money-safety</span><span class="cv ${sevOf(sys.moneySafety)}" style="color:${colorFor(sevOf(sys.moneySafety))}">${esc(sys.moneySafety)}</span></div>
      <div class="covitem"><span class="cn">Real IAP E2E</span><span class="cv" style="color:${colorFor('amber')}">${esc(sys.realIapE2E)}</span></div>
      <div class="covitem"><span class="cn">Observable</span><span class="cv">${cov.observable}/${cov.total}</span></div>
      <div class="covitem"><span class="cn">Direct probes</span><span class="cv">${cov.probed}/${cov.total}</span></div>
      <div class="covitem"><span class="cn">Critical paths</span><span class="cv">${cov.criticalPaths ? cov.criticalPaths.covered + '/' + cov.criticalPaths.total : '—'}</span></div>
      ${sys.canaryRunAt ? `<div class="covitem"><span class="cn">Canaries</span><span class="cv" style="font-size:11px">ran ${new Date(sys.canaryRunAt).toLocaleTimeString()}</span></div>` : ''}
    </div>
    ${why}`;
  host.querySelectorAll('[data-path]').forEach((c) => c.addEventListener('click', () => { if (c.dataset.path) centerNode(c.dataset.path); }));
  host.querySelectorAll('[data-goto]').forEach((c) => c.addEventListener('click', () => centerNode(c.dataset.goto)));
}
function svc(st, n) { return { status: (st && st.serviceHealth) || (n && n.status) || '—', severity: (st && st.serviceSeverity) || (n && n.severity) || 'grey', traffic: st && st.trafficState }; }

// ---------- render ----------
function renderAll() { renderCanvas(); renderLegend(); renderMinimap(); }
function renderCanvas() {
  const svg = $('#canvas'); svg.innerHTML = '';
  const vp = el('g', { id: 'viewport', transform: viewTransform() }); svg.appendChild(vp);
  S.gGroups = el('g'); S.gEdges = el('g'); S.gNodes = el('g');
  vp.appendChild(S.gGroups); vp.appendChild(S.gEdges); vp.appendChild(S.gNodes);
  renderGroups(); renderEdges();
  const hi = highlightSet();
  for (const n of S.topo.nodes) S.gNodes.appendChild(nodeEl(n, hi));
}
function renderGroups() {
  for (const g of (S.topo.groups || [])) {
    const dimGroup = S.tabSubset && !S.topo.nodes.some((n) => n.group === g.id && S.tabSubset.has(n.id));
    const wrap = el('g', dimGroup ? { opacity: 0.25 } : {});
    wrap.appendChild(el('rect', { class: 'grp-rect', x: g.x, y: g.y, width: g.w, height: g.h, rx: 16, ry: 16 }));
    const t = el('text', { class: 'grp-title', x: g.x + 20, y: g.y + 24 }); t.textContent = g.title; wrap.appendChild(t);
    const st = el('text', { class: 'grp-sub', x: g.x + 20, y: g.y + 24 }); st.setAttribute('dx', measure(g.title) + 14); st.textContent = g.subtitle; wrap.appendChild(st);
    S.gGroups.appendChild(wrap);
  }
}
function renderEdges() {
  if (!S.gEdges) return; S.gEdges.innerHTML = '';
  const hi = highlightSet();
  const tracePairIds = new Set(S.tracePath ? S.tracePath.map((e) => e.id) : []);
  const showLabels = S.view.k >= LABEL_ZOOM;
  for (const e of S.topo.edges) {
    const a = anchor(e.source, e.target, true), b = anchor(e.target, e.source, false);
    const d = curve(a, b);
    const inHi = hi && hi.has(e.source) && hi.has(e.target);
    const dim = (hi && !inHi) || (S.tabSubset && !(S.tabSubset.has(e.source) && S.tabSubset.has(e.target)));
    const sev = (S.statusById.get(e.source) || {}).severity || e.severity;
    const cls = ['edge', sev, e.animated ? 'animated' : '', dim ? 'faded' : '', inHi ? 'hl' : '', tracePairIds.has(e.id) ? 'trace' : ''].join(' ');
    S.gEdges.appendChild(el('path', { d, class: cls }));
    const hit = el('path', { d, class: 'edge-hit' }); hit.addEventListener('click', (ev) => { ev.stopPropagation(); openEdge(e); }); S.gEdges.appendChild(hit);
    if (showLabels && !dim) {
      const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2; const w = measure(e.type, 9.5) + 12;
      S.gEdges.appendChild(el('rect', { class: 'elabel-bg', x: mx - w / 2, y: my - 9, width: w, height: 16, rx: 5, ry: 5 }));
      const t = el('text', { class: 'elabel', x: mx, y: my + 2.5, 'text-anchor': 'middle' }); t.textContent = e.type; S.gEdges.appendChild(t);
    }
  }
}
function nodeEl(n, hi) {
  const p = S.pos.get(n.id); const w = NW(n), h = NH(n);
  const faded = (hi && !hi.has(n.id)) || (S.tabSubset && !S.tabSubset.has(n.id));
  const g = el('g', { class: 'node' + (S.sel === n.id ? ' sel' : '') + (hi && hi.has(n.id) ? ' hl' : '') + (faded ? ' faded' : ''), transform: `translate(${p.x},${p.y})`, 'data-id': n.id });
  const st = S.statusById.get(n.id); const sv = svc(st, n);
  const col = CAT_COLOR[n.category] || '#888';
  g.appendChild(el('rect', { class: 'glow', x: -3, y: -3, width: w + 6, height: h + 6, rx: 14, ry: 14, stroke: col }));
  g.appendChild(el('rect', { class: 'box', x: 0, y: 0, width: w, height: h, rx: 12, ry: 12 }));
  g.appendChild(el('rect', { class: 'accent', x: 0, y: 0, width: 6, height: h, rx: 3, ry: 3, fill: col }));
  g.appendChild(el('circle', { class: 'dot ' + sv.severity, cx: w - 18, cy: 18, r: 6.5 }));
  const cat = el('text', { class: 'cat', x: 16, y: 19, fill: col }); cat.textContent = n.category; g.appendChild(cat);
  const title = el('text', { class: 'title', x: 16, y: 42 }); title.textContent = clip(n.label, 22); g.appendChild(title);
  const role = el('text', { class: 'role', x: 16, y: 58 }); role.textContent = clip(n.role, 30); g.appendChild(role);
  // SERVICE health badge (bottom-left) + TRAFFIC state (distinct) + key metric
  const status = sv.status; const bw = measure(status, 11) + 16;
  g.appendChild(el('rect', { class: 'badge-bg ' + sv.severity, x: 14, y: h - 24, width: bw, height: 18, rx: 6, ry: 6, 'stroke-width': 1, 'data-badge-bg': 1 }));
  const bt = el('text', { class: 'badge ' + sv.severity, x: 14 + bw / 2, y: h - 11, 'text-anchor': 'middle', 'data-badge': 1 }); bt.textContent = status; g.appendChild(bt);
  let tx = 14 + bw + 10;
  if (sv.traffic && sv.traffic !== 'ACTIVE') { const tt = el('text', { class: 'traffic', x: tx, y: h - 11, 'data-traffic': 1 }); tt.textContent = 'Traffic: ' + sv.traffic.replace(' (no traffic)', ''); g.appendChild(tt); tx += measure(tt.textContent, 9.5) + 12; }
  const m = (st && st.metric) || n.metric;
  if (m && m.value !== 'N/A' && m.value != null) { const mt = el('text', { class: 'metricline', x: tx, y: h - 11 }); mt.textContent = `${m.label} ${m.value}${m.unit || ''}`; g.appendChild(mt); }
  attachNodeInteract(g, n.id);
  return g;
}
function updateNodeStatuses() {
  if (S.drag) return; // never re-patch mid-drag
  for (const n of S.topo.nodes) {
    const g = document.querySelector(`.node[data-id="${cssq(n.id)}"]`); if (!g) continue;
    const sv = svc(S.statusById.get(n.id), n);
    const dot = g.querySelector('.dot'); if (dot) dot.setAttribute('class', 'dot ' + sv.severity);
    const bb = g.querySelector('[data-badge-bg]'), bt = g.querySelector('[data-badge]');
    if (bb && bt) { const bw = measure(sv.status, 11) + 16; bb.setAttribute('class', 'badge-bg ' + sv.severity); bb.setAttribute('width', bw); bt.setAttribute('class', 'badge ' + sv.severity); bt.setAttribute('x', 14 + bw / 2); bt.textContent = sv.status; const tt = g.querySelector('[data-traffic]'); if (tt) tt.textContent = (sv.traffic && sv.traffic !== 'ACTIVE') ? 'Traffic: ' + sv.traffic.replace(' (no traffic)', '') : ''; }
  }
  renderEdges();
  renderMinimap();
}

// ---------- geometry / camera ----------
function nc(id) { const p = S.pos.get(id); const n = S.topo.nodes.find((x) => x.id === id); return { x: p.x + NW(n) / 2, y: p.y + NH(n) / 2, w: NW(n), h: NH(n), p }; }
// anchor on the node border toward the other node (cleaner arrows than center-to-center)
function anchor(id, otherId, isSource) {
  const c = nc(id); const o = nc(otherId); const dx = o.x - c.x, dy = o.y - c.y;
  const hw = c.w / 2 + 2, hh = c.h / 2 + 2;
  if (dx === 0 && dy === 0) return { x: c.x, y: c.y };
  const sx = dx === 0 ? Infinity : hw / Math.abs(dx), sy = dy === 0 ? Infinity : hh / Math.abs(dy); const s = Math.min(sx, sy);
  return { x: c.x + dx * s, y: c.y + dy * s };
}
function curve(a, b) { const dx = (b.x - a.x) * 0.28, dy = (b.y - a.y) * 0.55; return `M ${a.x} ${a.y} C ${a.x + dx} ${a.y + dy}, ${b.x - dx} ${b.y - dy}, ${b.x} ${b.y}`; }
function viewTransform() { return `translate(${S.view.x},${S.view.y}) scale(${S.view.k})`; }
function applyView() { const vp = $('#viewport'); if (vp) vp.setAttribute('transform', viewTransform()); drawMinimapViewport(); }
function contentBounds(ids) {
  const list = ids ? S.topo.nodes.filter((n) => ids.includes(n.id)) : S.topo.nodes;
  let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
  const src = ids ? list : (S.topo.groups && S.topo.groups.length ? S.topo.groups : list);
  for (const o of src) { const ox = o.x, oy = o.y, ow = o.w || NW(o), oh = o.h || NH(o); x0 = Math.min(x0, ox); y0 = Math.min(y0, oy); x1 = Math.max(x1, ox + ow); y1 = Math.max(y1, oy + oh); }
  if (ids) for (const o of list) { x0 = Math.min(x0, o.x); y0 = Math.min(y0, o.y); x1 = Math.max(x1, o.x + NW(o)); y1 = Math.max(y1, o.y + NH(o)); }
  return { x0, y0, x1, y1, w: x1 - x0, h: y1 - y0 };
}
function fitTo(ids, maxK) {
  const wrap = $('#canvas-wrap'); const b = contentBounds(ids); const pad = 60;
  const k = Math.min((wrap.clientWidth - pad) / b.w, (wrap.clientHeight - pad) / b.h, maxK || 1.1);
  S.view.k = Math.max(0.28, k);
  S.view.x = (wrap.clientWidth - b.w * S.view.k) / 2 - b.x0 * S.view.k;
  S.view.y = (wrap.clientHeight - b.h * S.view.k) / 2 - b.y0 * S.view.k;
  applyView(); renderEdges();
}
function resetView() { // readable default: centered horizontally, top of the map, not fit-to-death
  const wrap = $('#canvas-wrap'); const b = contentBounds(); S.view.k = 0.62;
  S.view.x = (wrap.clientWidth - b.w * S.view.k) / 2 - b.x0 * S.view.k;
  S.view.y = 24 - b.y0 * S.view.k; applyView(); if (S.gEdges) renderEdges();
}
function fitAll() { fitTo(null, 1.0); }
function fitSelection() { if (!S.sel) { fitAll(); return; } const set = new Set([S.sel, ...outAdj(S.sel), ...inAdj(S.sel)]); fitTo([...set], 1.0); }
function zoomBy(f) { const wrap = $('#canvas-wrap'); const mx = wrap.clientWidth / 2, my = wrap.clientHeight / 2; const nk = Math.max(0.25, Math.min(2.4, S.view.k * f)); S.view.x = mx - (mx - S.view.x) * (nk / S.view.k); S.view.y = my - (my - S.view.y) * (nk / S.view.k); S.view.k = nk; applyView(); renderEdges(); }

// ---------- interactions ----------
function attachNodeInteract(g, id) { g.addEventListener('mousedown', (ev) => { ev.stopPropagation(); const p = S.pos.get(id); S.drag = { id, g, mx: ev.clientX, my: ev.clientY, x: p.x, y: p.y, moved: false }; }); }
function wireGlobal() {
  const svg = $('#canvas'); let pan = null;
  svg.addEventListener('mousedown', (ev) => { pan = { mx: ev.clientX, my: ev.clientY, vx: S.view.x, vy: S.view.y }; svg.classList.add('grabbing'); });
  window.addEventListener('mousemove', (ev) => {
    if (S.drag) { const dx = (ev.clientX - S.drag.mx) / S.view.k, dy = (ev.clientY - S.drag.my) / S.view.k; if (Math.abs(dx) + Math.abs(dy) > 2) S.drag.moved = true; const nx = S.drag.x + dx, ny = S.drag.y + dy; S.pos.set(S.drag.id, { x: nx, y: ny }); S.drag.g.setAttribute('transform', `translate(${nx},${ny})`); renderEdges(); return; }
    if (pan) { S.view.x = pan.vx + (ev.clientX - pan.mx); S.view.y = pan.vy + (ev.clientY - pan.my); applyView(); }
  });
  window.addEventListener('mouseup', () => { if (S.drag) { if (!S.drag.moved) selectNode(S.drag.id); S.drag = null; } pan = null; svg.classList.remove('grabbing'); });
  svg.addEventListener('click', () => { if (S.mode !== 'trace') { S.sel = null; closeDrawer(); clearMode(); } });
  svg.addEventListener('wheel', (ev) => { ev.preventDefault(); const r = svg.getBoundingClientRect(); const mx = ev.clientX - r.left, my = ev.clientY - r.top; const f = ev.deltaY < 0 ? 1.12 : 1 / 1.12; const nk = Math.max(0.25, Math.min(2.4, S.view.k * f)); S.view.x = mx - (mx - S.view.x) * (nk / S.view.k); S.view.y = my - (my - S.view.y) * (nk / S.view.k); S.view.k = nk; applyView(); renderEdges(); }, { passive: false });

  document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => switchTab(t.dataset.tab)));
  $('#btn-deps').addEventListener('click', () => toggleMode('deps'));
  $('#btn-impact').addEventListener('click', () => toggleMode('impact'));
  $('#btn-trace').addEventListener('click', () => toggleMode('trace'));
  $('#btn-clear').addEventListener('click', () => { S.sel = null; closeDrawer(); clearMode(); });
  $('#btn-legend').addEventListener('click', () => $('#legend').classList.toggle('hidden'));
  $('#btn-refresh').addEventListener('click', refreshStatus);
  $('#btn-fit').addEventListener('click', fitAll);
  $('#btn-fitsel').addEventListener('click', fitSelection);
  $('#btn-reset').addEventListener('click', resetView);
  $('#btn-zoomin').addEventListener('click', () => zoomBy(1.2));
  $('#btn-zoomout').addEventListener('click', () => zoomBy(1 / 1.2));
  $('#btn-fs').addEventListener('click', toggleFullscreen);
  $('#btn-canary').addEventListener('click', async () => {
    const b = $('#btn-canary'); b.textContent = 'RUNNING…'; b.classList.add('on');
    try { const r = await api('/api/canary'); if (r.system) { S.system = r.system; renderSysHealth(); } await refreshStatus(); if (S.sel) selectNode(S.sel); }
    catch (e) { showBanner('canary run failed: ' + e.message); }
    b.textContent = 'RUN CANARIES'; b.classList.remove('on');
  });
  $('#search').addEventListener('input', (e) => onSearch(e.target.value));
  $('#search').addEventListener('keydown', (e) => { if (e.key === 'Enter') { const f = matchNodes(e.target.value)[0]; if (f) centerNode(f.id); } });
  window.addEventListener('resize', () => renderMinimap());
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { $('#legend').classList.add('hidden'); } });
}
function toggleMode(mode) {
  if (S.mode === mode) { clearMode(); return; }
  S.mode = mode; S.trace = []; S.tracePath = null;
  ['deps', 'impact', 'trace'].forEach((m) => $('#btn-' + m).classList.toggle('on', m === mode));
  $('#trace-hint').textContent = mode === 'trace' ? 'TRACE: click a source node, then a target.' : (S.sel ? '' : 'Select a node to ' + (mode === 'deps' ? 'show its dependencies.' : 'show its failure impact.'));
  renderCanvas();
}
function clearMode() { S.mode = 'none'; S.trace = []; S.tracePath = null; ['deps', 'impact', 'trace'].forEach((m) => $('#btn-' + m).classList.remove('on')); $('#trace-hint').textContent = ''; renderCanvas(); }

// ---------- focus / highlight ----------
function outAdj(id) { return S.topo.edges.filter((e) => e.source === id).map((e) => e.target); }
function inAdj(id) { return S.topo.edges.filter((e) => e.target === id).map((e) => e.source); }
function closure(id, adj) { const seen = new Set(); const q = [id]; while (q.length) { const c = q.shift(); for (const t of adj(c)) if (!seen.has(t)) { seen.add(t); q.push(t); } } seen.delete(id); return seen; }
function highlightSet() {
  if (S.mode === 'trace' && S.tracePath) { const s = new Set(); for (const e of S.tracePath) { s.add(e.source); s.add(e.target); } return s; }
  if (!S.sel) return null;
  if (S.mode === 'deps') return new Set([S.sel, ...closure(S.sel, inAdj), ...closure(S.sel, outAdj)]);
  if (S.mode === 'impact') return new Set([S.sel, ...closure(S.sel, outAdj)]);
  // plain select => focus on self + immediate neighbours
  return new Set([S.sel, ...outAdj(S.sel), ...inAdj(S.sel)]);
}

// ---------- selection + drawer ----------
async function selectNode(id) {
  if (S.mode === 'trace') { handleTracePick(id); return; }
  S.sel = id; renderCanvas();
  const d = await api('/api/node/' + encodeURIComponent(id)); openDrawer(d);
}
function centerNode(id) { const p = S.pos.get(id); const n = S.topo.nodes.find((x) => x.id === id); const wrap = $('#canvas-wrap'); S.view.k = Math.max(S.view.k, 0.85); S.view.x = wrap.clientWidth / 2 - (p.x + NW(n) / 2) * S.view.k; S.view.y = wrap.clientHeight / 2 - (p.y + NH(n) / 2) * S.view.k; applyView(); selectNode(id); }
function centerOn(id){ centerNode(id); }

function section(key, title, bodyHtml, closedDefault) {
  const closed = S.drawerClosed[key] ?? !!closedDefault;
  return `<div class="sec ${closed ? 'closed' : ''}" data-sec="${key}"><div class="sec-h">${title}<span class="arw">▾</span></div><div class="sec-b">${bodyHtml}</div></div>`;
}
function openDrawer(d) {
  const dr = $('#drawer'); dr.classList.add('open');
  const list = (arr) => arr && arr.length ? `<div class="chiprow">${arr.map((x) => `<span class="chip" data-goto="${esc(x.id)}">${esc(x.label)}</span>`).join('')}</div>` : '<span class="hint">none</span>';
  const codes = (arr) => arr && arr.length ? `<div class="chiprow">${arr.map((c) => `<span class="chip code">${esc(c)}</span>`).join('')}</div>` : '<span class="hint">none</span>';
  const rbs = (arr) => arr && arr.length ? `<div class="chiprow">${arr.map((c) => `<span class="chip rb">${esc(c)}</span>`).join('')}</div>` : '<span class="hint">none</span>';
  const srcs = (arr) => arr && arr.length ? `<div class="chiprow">${arr.map((c) => `<span class="chip src">${esc(c)}</span>`).join('')}</div>` : '<span class="hint">none</span>';
  const ev = (d.recentEvents || []).slice(0, 25).map((e) => `<div class="evrow"><span class="sev ${e.severity}">${e.severity[0]}</span><span>${esc(e.event)}</span><span class="hint">${e.time ? new Date(e.time).toLocaleTimeString() : ''}</span></div>`).join('') || '<span class="hint">no recent events for this domain</span>';
  const H = d.health || {};
  const svcPill = pill(H.serviceHealth || d.status, H.severity || d.severity);
  const healthBody = `
    <div class="kvline"><span class="hint">Service</span> ${svcPill}${H.canary ? `<span class="hint" style="margin-left:8px">canary ${esc(H.canary)}${H.canaryStatus ? ': ' + esc(H.canaryStatus) : ' — not run'}</span>` : ''}</div>
    ${H.trafficState ? `<div class="kvline"><span class="hint">Traffic</span> <b>${esc(H.trafficState)}</b></div>` : ''}
    ${H.business ? `<div class="kvline"><span class="hint">Money-safety</span> ${pill(H.business, sevOf(H.business))}</div>` : ''}
    <div class="kvline"><span class="hint">Direct probe</span> <b>${H.probe ? 'yes' : 'no'}</b> · <span class="hint">On critical path</span> <b>${H.e2e ? (H.paths || []).join(', ') : 'no'}</b></div>
    ${(H.naReason) ? `<div class="nabox"><b>Health signal:</b> ${esc(H.naReason)}${H.recommend ? `<br><b>Recommended monitoring:</b> ${esc(H.recommend)}` : ''}</div>` : ''}`;
  dr.innerHTML = `<div class="d-inner">
    <h2>${esc(d.label)} ${svcPill}<button class="close" data-close>×</button></h2>
    <div class="sub">${esc(d.category)} · ${esc(d.role)}</div>
    <div class="desc">${esc(d.description)}</div>
    ${section('health', 'Health', healthBody)}
    ${section('metrics', 'Current metrics', d.metric ? `<div class="metricbig">${esc(String(d.metric.value))}${esc(d.metric.unit || '')}</div><span class="hint">${esc(d.metric.label)}</span>` : '<span class="hint">no key metric — N/A</span>', true)}
    ${section('conn', 'Connections', `<b class="hint">Depends On</b>${list(d.dependsOn)}<div style="height:8px"></div><b class="hint">Used By</b>${list(d.usedBy)}<div style="height:8px"></div><b class="hint">Observed By</b>${list(d.observedBy)}`)}
    ${section('impact', 'Failure impact', list(d.downstreamImpact))}
    ${section('obs', 'Observability — alert codes', codes(d.alertCodes))}
    ${section('rb', 'Runbook sections', rbs(d.runbook))}
    ${section('src', 'Source files', srcs(d.sources), true)}
    ${section('ev', 'Recent events', ev)}
    <div class="sec"><div class="sec-h">Last update<span class="hint" style="text-transform:none">${d.lastUpdate ? new Date(d.lastUpdate).toLocaleString() : '—'}</span></div></div>
  </div>`;
  dr.querySelector('[data-close]').addEventListener('click', () => { S.sel = null; closeDrawer(); clearMode(); });
  dr.querySelectorAll('[data-goto]').forEach((c) => c.addEventListener('click', () => centerNode(c.dataset.goto)));
  dr.querySelectorAll('.sec[data-sec] > .sec-h').forEach((h) => h.addEventListener('click', () => { const sec = h.parentElement; const k = sec.dataset.sec; sec.classList.toggle('closed'); S.drawerClosed[k] = sec.classList.contains('closed'); }));
}
function openEdge(e) {
  const dr = $('#drawer'); dr.classList.add('open'); S.sel = null; renderCanvas();
  const nm = (id) => { const n = S.topo.nodes.find((x) => x.id === id); return n ? n.label : id; };
  const row = (k, v) => v ? `<div class="sec"><div class="sec-h" style="cursor:default">${k}</div><div class="sec-b" style="display:block"><div class="desc" style="margin:0">${esc(v)}</div></div></div>` : '';
  dr.innerHTML = `<div class="d-inner">
    <h2>${esc(nm(e.source))} → ${esc(nm(e.target))}<button class="close" data-close>×</button></h2>
    <div class="sub">RELATION · ${esc(e.type)}</div>
    ${row('Purpose', e.purpose)}${row('Input', e.input)}${row('Output', e.output)}${row('Security boundary', e.security)}${row('Failure behavior', e.failure)}${row('Observability coverage', e.observability)}
  </div>`;
  dr.querySelector('[data-close]').addEventListener('click', () => closeDrawer());
}
function closeDrawer() { $('#drawer').classList.remove('open'); }

// ---------- trace ----------
function handleTracePick(id) {
  S.trace.push(id);
  if (S.trace.length === 1) { $('#trace-hint').textContent = `TRACE: from ${label(id)} → click target…`; S.sel = id; renderCanvas(); return; }
  const [from, to] = S.trace; S.trace = []; const path = clientPath(from, to); S.tracePath = path;
  $('#trace-hint').textContent = path.length ? `PATH ${label(from)} → ${label(to)} (${path.length} hops)` : `No directed path ${label(from)} → ${label(to)}`;
  renderCanvas();
}
function clientPath(from, to) { if (from === to) return []; const prev = new Map(); const q = [from]; const seen = new Set([from]); while (q.length) { const c = q.shift(); for (const e of S.topo.edges) if (e.source === c && !seen.has(e.target)) { seen.add(e.target); prev.set(e.target, e); if (e.target === to) { const p = []; let cur = to; while (prev.has(cur)) { const ed = prev.get(cur); p.unshift(ed); cur = ed.source; } return p; } q.push(e.target); } } return []; }

// ---------- search / tabs / logs ----------
function matchNodes(q) { q = (q || '').trim().toLowerCase(); if (!q) return []; return S.topo.nodes.filter((n) => n.label.toLowerCase().includes(q) || n.id.includes(q) || n.category.toLowerCase().includes(q)); }
function onSearch(q) { const set = new Set(matchNodes(q).map((n) => n.id)); document.querySelectorAll('.node').forEach((g) => g.classList.toggle('faded', q && !set.has(g.dataset.id))); }
function switchTab(tab) {
  S.tab = tab; document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === tab));
  const wrap = $('#canvas-wrap');
  if (tab === 'logs') { wrap.classList.add('hidden'); showLogs(); return; }
  wrap.classList.remove('hidden'); removeLogs();
  S.tabSubset = TAB_SUBSET[tab] ? new Set(TAB_SUBSET[tab]) : null;
  renderCanvas();
  if (tab === 'map') { $('#panel').classList.add('hidden'); resetView(); } else { renderInfoPanel(); if (TAB_SUBSET[tab]) fitTo(TAB_SUBSET[tab], 0.95); }
}
function renderInfoPanel() {
  const p = $('#panel'); p.classList.remove('hidden'); const m = S.meta || {}; const stat = (id) => (S.statusById.get(id) || {}).status || '—';
  const kv = (k, v, cls) => `<div class="kv"><span class="k">${k}</span>${cls ? pill(v, cls) : `<span>${esc(v)}</span>`}</div>`;
  if (S.tab === 'runtime') p.innerHTML = `<h3>RUNTIME</h3>${kv('Collector', stat('collector'), sevOf(stat('collector')))}${kv('Railway', stat('railway'), sevOf(stat('railway')))}${kv('Postgres', stat('postgres'), sevOf(stat('postgres')))}${kv('OpenAI', stat('openai'), sevOf(stat('openai')))}${kv('Security', stat('security_domain'), sevOf(stat('security_domain')))}${kv('Service', stat('service_domain'), sevOf(stat('service_domain')))}${kv('Collector freshness', (m.collectorFreshnessMin != null ? m.collectorFreshnessMin + ' min' : 'N/A'))}`;
  else if (S.tab === 'incidents') p.innerHTML = `<h3>INCIDENT PIPELINE</h3>${kv('Delivery mode', m.incidentMode || '—', sevOf(m.incidentMode))}${kv('Active critical', String(m.activeCritical ?? '—'), (m.activeCritical > 0 ? 'red' : 'green'))}${kv('Canonical writer', 'ONE', 'green')}${kv('Legacy writer', 'OFF', 'green')}${kv('Slack for incidents', 'NO', 'green')}<div class="kv"><span class="k">Path</span><span>Evaluator → Incident Engine → GitHub Issues</span></div>`;
  else if (S.tab === 'iap') p.innerHTML = `<h3>IAP MONEY-SAFETY</h3>${IAP_INVARIANTS.map((c) => { const bad = stat('iap_verify') === 'UNHEALTHY'; return `<div class="kv"><span class="k" style="font-size:10.5px">${c}</span>${pill(bad ? 'CHECK' : 'OK', bad ? 'red' : 'green')}</div>`; }).join('')}${kv('IAP domain', stat('iap_verify'), sevOf(stat('iap_verify')))}${kv('Real IAP TestFlight E2E', m.realIapE2E || 'DEFERRED', 'amber')}`;
  else if (S.tab === 'release') p.innerHTML = `<h3>RELEASE CHAIN</h3>${kv('Observability Platform', m.observabilityPlatform || '—', sevOf(m.observabilityPlatform))}${kv('Runtime Validation', m.runtimeValidation || '—', sevOf(m.runtimeValidation))}${kv('Real IAP E2E', m.realIapE2E || 'DEFERRED', 'amber')}${kv('Product Release Gate', m.gate || '—', sevOf(m.gate))}<div class="kv"><span class="k">Chain</span><span>Platform → Validation → Gate</span></div>`;
}
let logState = { domain: 'ALL', severity: 'ALL' };
async function showLogs() {
  let host = $('#logs'); if (!host) { host = document.createElement('div'); host.id = 'logs'; host.className = 'logs'; $('.stage').insertBefore(host, $('#drawer')); }
  const doms = ['ALL', 'IAP', 'OPENAI', 'RAILWAY', 'POSTGRES', 'COLLECTOR', 'INCIDENT', 'SLACK', 'SECURITY', 'SERVICE'];
  const sevs = ['ALL', 'INFO', 'WARNING', 'CRITICAL'];
  host.innerHTML = `<div class="filters">${doms.map((d) => `<button class="fbtn ${logState.domain === d ? 'on' : ''}" data-dom="${d}">${d}</button>`).join('')}<span style="width:14px"></span>${sevs.map((s) => `<button class="fbtn ${logState.severity === s ? 'on' : ''}" data-sev="${s}">${s}</button>`).join('')}</div>
    <table><thead><tr><th>Time</th><th>Domain</th><th>Event</th><th>Severity</th><th>Status</th><th>Source</th></tr></thead><tbody id="logbody"><tr><td colspan="6" class="hint">loading…</td></tr></tbody></table>`;
  host.querySelectorAll('[data-dom]').forEach((b) => b.addEventListener('click', () => { logState.domain = b.dataset.dom; showLogs(); }));
  host.querySelectorAll('[data-sev]').forEach((b) => b.addEventListener('click', () => { logState.severity = b.dataset.sev; showLogs(); }));
  const r = await api(`/api/events?domain=${logState.domain}&severity=${logState.severity}`);
  const body = $('#logbody');
  if (!r.events || !r.events.length) { body.innerHTML = `<tr><td colspan="6" class="hint">${r.present ? 'no matching events' : 'no artifact — run npm run ops:fetch'}</td></tr>`; return; }
  body.innerHTML = r.events.map((e) => `<tr><td class="hint">${e.time ? new Date(e.time).toLocaleTimeString() : '—'}</td><td>${esc(e.domain)}</td><td>${esc(e.event)}</td><td class="sev ${e.severity}">${e.severity}</td><td>${esc(e.status || '')}</td><td class="hint">${esc(e.source || '')}</td></tr>`).join('');
}
function removeLogs() { const h = $('#logs'); if (h) h.remove(); }

// ---------- legend / minimap / fullscreen ----------
function renderLegend() {
  const sw = (c, t) => `<div class="row"><span class="sw" style="background:${c}"></span>${t}</div>`;
  const ln = (c, t) => `<div class="row"><span class="ln" style="border-color:${c}"></span>${t}</div>`;
  $('#legend').innerHTML =
    `<h5>Node types</h5>${CAT_LABELS.map((c) => sw(CAT_COLOR[c], c.replace('_', ' ').toLowerCase())).join('')}` +
    `<h5>Edge types</h5>${EDGE_TYPES.map((t) => ln('#5a6b80', t.replace('_', ' '))).join('')}` +
    `<h5>Status</h5>${sw('#2ea043', 'healthy / live / full / verified')}${sw('#d29922', 'idle / warn / partial / deferred')}${sw('#f85149', 'unhealthy / critical / block')}${sw('#6e7681', 'unknown / n/a / not configured')}`;
}
function renderMinimap() {
  const mm = $('#minimap'); mm.innerHTML = ''; const b = contentBounds(); const pad = 10; const k = Math.min((230 - pad * 2) / b.w, (165 - pad * 2) / b.h); mm.dataset.k = k; mm.dataset.x0 = b.x0; mm.dataset.y0 = b.y0; mm.dataset.pad = pad;
  const g = el('g', { transform: `translate(${pad - b.x0 * k},${pad - b.y0 * k}) scale(${k})` }); mm.appendChild(g);
  for (const gr of (S.topo.groups || [])) g.appendChild(el('rect', { x: gr.x, y: gr.y, width: gr.w, height: gr.h, rx: 12, fill: '#1a2231', stroke: '#2b3648', 'stroke-width': 2 }));
  for (const n of S.topo.nodes) { const p = S.pos.get(n.id); const st = S.statusById.get(n.id) || {}; g.appendChild(el('rect', { x: p.x, y: p.y, width: NW(n), height: NH(n), rx: 8, fill: colorFor(st.severity || n.severity), opacity: (n.id === S.sel ? 1 : 0.85), stroke: n.id === S.sel ? '#fff' : 'none', 'stroke-width': n.id === S.sel ? 10 : 0 })); }
  mm.appendChild(el('rect', { id: 'mmview', fill: 'none', stroke: '#58a6ff', 'stroke-width': 3 }));
  drawMinimapViewport();
}
function drawMinimapViewport() {
  const mm = $('#minimap'); const rect = mm && mm.querySelector('#mmview'); if (!rect) return; const wrap = $('#canvas-wrap'); const k = +mm.dataset.k, x0 = +mm.dataset.x0, y0 = +mm.dataset.y0, pad = +mm.dataset.pad;
  const vx = (-S.view.x / S.view.k), vy = (-S.view.y / S.view.k), vw = wrap.clientWidth / S.view.k, vh = wrap.clientHeight / S.view.k;
  rect.setAttribute('x', pad + (vx - x0) * k); rect.setAttribute('y', pad + (vy - y0) * k); rect.setAttribute('width', Math.max(4, vw * k)); rect.setAttribute('height', Math.max(4, vh * k));
}
function toggleFullscreen() { if (!document.fullscreenElement) { document.documentElement.requestFullscreen && document.documentElement.requestFullscreen(); } else { document.exitFullscreen && document.exitFullscreen(); } }

// ---------- utils ----------
function sevOf(v) { const s = (v || '').toString().toUpperCase(); if (['HEALTHY', 'FULL', 'LIVE', 'VERIFIED', 'PASS', 'OK'].includes(s)) return 'green'; if (['WARN', 'PARTIAL', 'DEFERRED', 'IDLE', 'DEGRADED'].includes(s)) return 'amber'; if (['CRITICAL', 'BLOCK', 'UNHEALTHY', 'DOWN', 'FAILED', 'UNAVAILABLE'].includes(s)) return 'red'; return 'grey'; }
function colorFor(sev) { return { green: '#2ea043', amber: '#d29922', red: '#f85149', grey: '#6e7681' }[sev] || '#6e7681'; }
function label(id) { const n = S.topo.nodes.find((x) => x.id === id); return n ? n.label : id; }
function measure(s, px = 14) { return String(s || '').length * px * 0.58; }
function clip(s, n) { s = String(s || ''); return s.length > n ? s.slice(0, n - 1) + '…' : s; }
function pill(v, cls) { return `<span class="pill ${cls}">${esc(v)}</span>`; }
function esc(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
function cssq(s) { return String(s).replace(/"/g, '\\"'); }
function showBanner(t) { const b = $('#banner'); b.textContent = t; b.classList.remove('hidden'); }
function hideBanner() { $('#banner').classList.add('hidden'); }
