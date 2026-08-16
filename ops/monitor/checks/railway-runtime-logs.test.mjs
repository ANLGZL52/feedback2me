// Railway runtime-log collector tests. No network — deps.fetchLogs is injected.
// Run: node --test ops/monitor/checks/railway-runtime-logs.test.mjs
import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { collect, normalizeLogLine, redact, canonicalRoute } from './railway-runtime-logs.mjs';

const ENV = 'OPS_RAILWAY_TOKEN';
afterEach(() => { delete process.env[ENV]; });
const fetchLogsReturning = (logs, extra = {}) => async () => ({ auth: 'OK', logs, deploymentId: 'dep-1', ...extra });

test('TEST 1: successful request line → safe completion event (metadata only)', () => {
  const e = normalizeLogLine({ message: JSON.stringify({ evt: 'server.request.completed', method: 'POST', route: '/feedbacks', status: 201, ms: 42, cid: 'r-1' }) });
  assert.equal(e.eventType, 'server.request.completed');
  assert.equal(e.statusClass, '2xx');
  assert.equal(e.latencyMs, 42);
  assert.equal(e.correlationId, 'r-1');
});

test('TEST 2: failed request → runtime failure event', () => {
  const e = normalizeLogLine({ message: JSON.stringify({ evt: 'server.request.failed', method: 'POST', route: '/feedbacks', status: 500, ms: 9, code: 'INTERNAL_ERROR', cid: 'r-2' }) });
  assert.equal(e.eventType, 'server.request.failed');
  assert.equal(e.statusClass, '5xx');
  assert.equal(e.errorCode, 'INTERNAL_ERROR');
});

test('TEST 3: request body with feedback text → feedback text absent from event', () => {
  const e = normalizeLogLine({ message: JSON.stringify({ evt: 'server.request.completed', method: 'POST', route: '/feedbacks', status: 201, ms: 5, cid: 'r', body: 'the product is terrible and my name is Jane' }) });
  const s = JSON.stringify(e);
  assert.ok(!s.includes('terrible'), 'feedback text leaked');
  assert.ok(!s.includes('Jane'), 'name leaked');
});

test('TEST 4/5: Authorization + Cookie in a plaintext line → redacted', () => {
  const s = redact('req headers authorization: Bearer eyJabc.def.ghi cookie: session=secret123');
  assert.ok(!s.includes('eyJabc'), 'jwt leaked');
  assert.ok(!/session=secret123/.test(s), 'cookie value leaked');
});

test('TEST 6: DB error containing DATABASE_URL → credential absent', () => {
  const e = normalizeLogLine({ severity: 'error', message: 'db error connecting to postgres://user:pw@host:5432/railway failed' });
  const s = JSON.stringify(e);
  assert.ok(!s.includes('pw@host'), 'db credential leaked');
  assert.ok(s.includes('<redacted>'), 'not redacted');
});

test('TEST 7: OpenAI error with key/prompt → key/prompt absent', () => {
  const s = redact('openai call failed apiKey=sk-ABCDEFGHIJKLMNOP1234 prompt="user feedback here"');
  assert.ok(!s.includes('sk-ABCDEFGHIJKLMNOP1234'), 'api key leaked');
});

test('TEST 8: JWT error line → token absent', () => {
  const s = redact('jwt verify failed for eyJhbGciOi.JzdWIiOiJ.abc123');
  assert.ok(!/eyJhbGciOi\.JzdWIiOiJ\.abc123/.test(s), 'jwt leaked');
});

test('TEST 9: dynamic URL with a private code → canonical route only', () => {
  assert.equal(canonicalRoute('GET', '/public/links/SECRETCODE123?x=1'), 'GET /public/links/:code');
  assert.equal(canonicalRoute('POST', '/feedbacks/abc-private'), 'POST /feedbacks/:code');
});

test('TEST 10: correlationId propagated from a structured db-failure event', () => {
  const e = normalizeLogLine({ message: JSON.stringify({ evt: 'db.operation.failed', component: 'node-postgres', dbOp: 'READ', code: 'DB_QUERY_FAILED', cid: 'op-77' }) });
  assert.equal(e.correlationId, 'op-77');
  assert.equal(e.componentId, 'node-postgres');
  assert.equal(e.dbOperationCategory, 'READ');
});

test('TEST 12: unknown raw log format → ignored (null), not emitted', () => {
  assert.equal(normalizeLogLine({ message: 'Starting Container' }), null);
  assert.equal(normalizeLogLine({ message: '{"random":"json without evt"}' }), null);
  assert.equal(normalizeLogLine({ message: 'some infra chatter' }), null);
});

test('TEST 14: OPS_RAILWAY_TOKEN absent → UNKNOWN / NOT_CONFIGURED (not a backend outage)', async () => {
  delete process.env[ENV];
  const r = await collect({});
  assert.equal(r.status, 'UNKNOWN');
  assert.equal(r.errorCode, 'NOT_CONFIGURED');
  assert.deepEqual(r.events, []);
});

test('TEST 15: Railway auth failure → collector DOWN/RAILWAY_AUTH_FAILED (distinct from backend outage)', async () => {
  const r = await collect({ token: 'x' }, { fetchLogs: async () => ({ auth: 'FAILED', logs: null }) });
  assert.equal(r.status, 'DOWN');
  assert.equal(r.errorCode, 'RAILWAY_AUTH_FAILED');
});

test('TEST 13: collector timeout → does not hang (TIMEOUT)', async () => {
  const r = await collect({ token: 'x' }, { fetchLogs: async () => { const e = new Error('abort'); e.name = 'AbortError'; throw e; } });
  assert.equal(r.status, 'DOWN');
  assert.equal(r.errorCode, 'TIMEOUT');
});

test('collect: mixed logs → only recognized safe events emitted, raw lines dropped', async () => {
  process.env[ENV] = 'tok';
  const r = await collect({}, { fetchLogs: fetchLogsReturning([
    { message: 'Starting Container', severity: 'info' },
    { message: 'listening http://0.0.0.0:8080', severity: 'info' },
    { message: JSON.stringify({ evt: 'server.request.failed', method: 'POST', route: '/feedbacks/CODE', status: 500, code: 'DB_QUERY_FAILED', cid: 'c1' }), severity: 'error' },
    { message: 'random infra line', severity: 'info' },
  ]) });
  assert.equal(r.status, 'HEALTHY');
  assert.equal(r.logLinesScanned, 4);
  assert.equal(r.events.length, 2); // startup.ok + request.failed; the 2 infra lines dropped
  const failed = r.events.find((e) => e.eventType === 'server.request.failed');
  assert.equal(failed.routeId, 'POST /feedbacks/:code'); // canonicalized, no real code
  assert.ok(!JSON.stringify(r).includes('/feedbacks/CODE'));
});

// Phase 18: safe dedup fingerprint (componentId+eventType+errorCode+routeId+statusClass).
test('dedup fingerprint uses only safe fields, never raw content', () => {
  const fp = (e) => [e.componentId, e.eventType, e.errorCode, e.routeId, e.statusClass].join('|');
  const a = normalizeLogLine({ message: JSON.stringify({ evt: 'server.request.failed', method: 'POST', route: '/feedbacks/A', status: 500, code: 'DB_QUERY_FAILED', cid: 'x' }) });
  const b = normalizeLogLine({ message: JSON.stringify({ evt: 'server.request.failed', method: 'POST', route: '/feedbacks/B', status: 500, code: 'DB_QUERY_FAILED', cid: 'y' }) });
  assert.equal(fp(a), fp(b)); // same fingerprint despite different codes/cids
  assert.ok(!fp(a).includes('/feedbacks/A'));
});
