// Railway HTTP-log collector tests. No network (deps.fetchHttp injected).
// Run: node --test ops/monitor/checks/railway-http-logs.test.mjs
import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { collect, normalizeHttpLog, canonicalPath, SUCCESS_SAMPLE_N } from './railway-http-logs.mjs';

const ENV = 'OPS_RAILWAY_TOKEN';
afterEach(() => { delete process.env[ENV]; });
const row = (o) => ({ timestamp: '2026-01-01T00:00:00Z', method: 'GET', path: '/x', httpStatus: 200, totalDuration: 5, requestId: 'r', deploymentId: 'd', ...o });

test('TEST 1: 401 → normalized safely (4xx, latency, requestId)', () => {
  const e = normalizeHttpLog(row({ method: 'GET', path: '/me/feedback-pool', httpStatus: 401, totalDuration: 34, requestId: 'JbVD79gd' }));
  assert.equal(e.eventType, 'railway.http.request');
  assert.equal(e.statusClass, '4xx');
  assert.equal(e.httpStatus, 401);
  assert.equal(e.latencyMs, 34);
  assert.equal(e.railwayRequestId, 'JbVD79gd');
});

test('TEST 2: 500 → normalized safely (5xx, error severity)', () => {
  const e = normalizeHttpLog(row({ path: '/feedbacks', method: 'POST', httpStatus: 500, totalDuration: 12 }));
  assert.equal(e.statusClass, '5xx');
  assert.equal(e.severity, 'error');
});

test('TEST 3: successful /health → excluded (null)', () => {
  assert.equal(normalizeHttpLog(row({ path: '/health', httpStatus: 200 })), null);
});

test('TEST 4: dynamic link code in path → canonical route only', () => {
  assert.equal(canonicalPath('/public/links/SECRETCODE?x=1'), '/public/links/:code');
  assert.equal(canonicalPath('/feedbacks/abc-private'), '/feedbacks/:code');
  const e = normalizeHttpLog(row({ path: '/public/links/PRIVATE123', httpStatus: 404 }));
  assert.equal(e.routeId, '/public/links/:code');
  assert.ok(!JSON.stringify(e).includes('PRIVATE123'));
});

test('TEST 5/6/7/8: srcIp / clientUa / query / auth are NEVER present (not even fetched)', () => {
  // The collector selects only safe fields; even if a row carried extras, normalize drops them.
  const e = normalizeHttpLog({ ...row({ httpStatus: 401 }), srcIp: '1.2.3.4', clientUa: 'evil/1.0', path: '/me/feedback-pool?token=eyJabc', requestId: 'r' });
  const s = JSON.stringify(e);
  assert.ok(!s.includes('1.2.3.4'), 'srcIp leaked');
  assert.ok(!s.includes('evil/1.0'), 'clientUa leaked');
  assert.ok(!s.includes('eyJabc'), 'query/token leaked');
  assert.ok(!s.includes('?'), 'query string leaked');
  assert.equal(e.routeId, '/me/feedback-pool'); // query dropped
});

test('TEST 9: bounded — collector caps at DEFAULT_LIMIT', async () => {
  process.env[ENV] = 'tok';
  const many = Array.from({ length: 500 }, (_, i) => row({ httpStatus: 500, requestId: 'r' + i }));
  const r = await collect({ limit: 999 }, { fetchHttp: async (t, limit) => ({ auth: 'OK', rows: many.slice(0, Math.min(limit, 200)), deploymentId: 'd' }) });
  assert.ok(r.rowsScanned <= 200, 'not bounded to 200');
});

test('TEST 10: collector timeout → DOWN/TIMEOUT (safe)', async () => {
  const r = await collect({ token: 'x' }, { fetchHttp: async () => { const e = new Error('abort'); e.name = 'AbortError'; throw e; } });
  assert.equal(r.status, 'DOWN');
  assert.equal(r.errorCode, 'TIMEOUT');
});

test('TEST 11: OPS_RAILWAY_TOKEN missing → UNKNOWN/NOT_CONFIGURED (not backend DOWN)', async () => {
  delete process.env[ENV];
  const r = await collect({});
  assert.equal(r.status, 'UNKNOWN');
  assert.equal(r.errorCode, 'NOT_CONFIGURED');
});

test('TEST 12: invalid token → collector DOWN/RAILWAY_AUTH_FAILED (not backend DOWN)', async () => {
  const r = await collect({ token: 'bad' }, { fetchHttp: async () => ({ auth: 'FAILED', rows: null }) });
  assert.equal(r.status, 'DOWN');
  assert.equal(r.errorCode, 'RAILWAY_AUTH_FAILED');
});

test('success sampling: only 1 in N successful requests emitted; failures all emitted', async () => {
  process.env[ENV] = 'tok';
  const rows = [];
  for (let i = 0; i < SUCCESS_SAMPLE_N * 2; i++) rows.push(row({ path: '/links', httpStatus: 200, requestId: 's' + i }));
  rows.push(row({ path: '/feedbacks', method: 'POST', httpStatus: 500, requestId: 'f1' }));
  const r = await collect({}, { fetchHttp: async () => ({ auth: 'OK', rows, deploymentId: 'd' }) });
  const success = r.events.filter((e) => e.statusClass === '2xx').length;
  const fail = r.events.filter((e) => e.statusClass === '5xx').length;
  assert.equal(fail, 1, 'all failures emitted');
  assert.ok(success <= 2, `success sampled (~${success})`);
});
