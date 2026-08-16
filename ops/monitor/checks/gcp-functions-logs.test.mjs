// GCP Cloud Functions log-collector tests. No network (deps.fetchEntries injected).
// Run: node --test ops/monitor/checks/gcp-functions-logs.test.mjs
import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { collect, normalizeLogEntry, classifyGcp } from './gcp-functions-logs.mjs';

const ENV = 'GCP_ACCESS_TOKEN';
afterEach(() => { delete process.env[ENV]; });
// 2nd-gen function log entry (cloud_run_revision)
const entry = (o = {}) => ({
  timestamp: '2026-01-01T00:00:00Z', severity: 'INFO',
  resource: { type: 'cloud_run_revision', labels: { service_name: 'iapverify', location: 'us-central1', revision_name: 'iapverify-001' } },
  labels: { execution_id: 'exec-123' }, textPayload: 'ok', ...o,
});

test('TEST 1: safe execution log → normalized gcp.function.execution', () => {
  const e = normalizeLogEntry(entry());
  assert.equal(e.eventType, 'gcp.function.execution');
  assert.equal(e.service, 'iapverify');
  assert.equal(e.region, 'us-central1');
  assert.equal(e.gcpExecutionId, 'exec-123');
});

test('TEST 2: ERROR log → safe error code (gcp.function.error)', () => {
  const e = normalizeLogEntry(entry({ severity: 'ERROR', textPayload: 'deadline exceeded' }));
  assert.equal(e.eventType, 'gcp.function.error');
  assert.equal(e.errorCode, 'FUNCTION_TIMEOUT');
});

test('TEST 3: raw message contains email → email absent from event', () => {
  const e = normalizeLogEntry(entry({ severity: 'ERROR', textPayload: 'failed for jane.doe@example.com' }));
  assert.ok(!JSON.stringify(e).includes('jane.doe@example.com'), 'email leaked');
});

test('TEST 4: raw message contains JWT → token absent', () => {
  const e = normalizeLogEntry(entry({ severity: 'ERROR', textPayload: 'bad token eyJhbGciOiJIUzI1.eyJzdWIiOiIx.SflKxwRJSMeK' }));
  assert.ok(!JSON.stringify(e).includes('eyJhbGciOiJIUzI1'), 'jwt leaked');
});

test('TEST 5: IAP receipt / purchase token in payload → absent', () => {
  const e = normalizeLogEntry(entry({ severity: 'ERROR', jsonPayload: { message: 'verify failed', purchaseToken: 'PT-SECRET-abc', receipt: 'RCPT-xyz' } }));
  const s = JSON.stringify(e);
  assert.ok(!s.includes('PT-SECRET-abc') && !s.includes('RCPT-xyz'), 'iap token/receipt leaked');
});

test('TEST 6: stack trace containing a secret → raw stack absent', () => {
  const e = normalizeLogEntry(entry({ severity: 'ERROR', jsonPayload: { stack: 'Error: db postgres://u:pw@h/db\n  at x' } }));
  assert.ok(!JSON.stringify(e).includes('pw@h'), 'stack/secret leaked');
  assert.equal(e.errorCode, 'FUNCTION_RUNTIME_ERROR');
});

test('TEST 7: execution_id available → retained safely', () => {
  assert.equal(normalizeLogEntry(entry({ labels: { execution_id: 'E7' } })).gcpExecutionId, 'E7');
});

test('TEST 8: no execution_id → event still valid (null id)', () => {
  const e = normalizeLogEntry(entry({ labels: {} }));
  assert.ok(e);
  assert.equal(e.gcpExecutionId, null);
});

test('TEST 9: unrelated GCP service log (e.g. gce_instance) → ignored (null)', () => {
  assert.equal(normalizeLogEntry(entry({ resource: { type: 'gce_instance', labels: {} } })), null);
});

test('TEST 10/11: query + pagination bounded (single page, capped pageSize)', async () => {
  process.env[ENV] = 'tok';
  let sawPageSize = 0, calls = 0;
  const r = await collect({ pageSize: 999 }, { fetchEntries: async (t, p, ps) => { calls++; sawPageSize = ps; return { auth: 'OK', entries: [] }; } });
  assert.ok(sawPageSize <= 50, 'pageSize not capped');
  assert.equal(calls, 1, 'more than one page fetched');
  assert.equal(r.status, 'HEALTHY');
});

test('TEST 12: timeout → DOWN/TIMEOUT (safe)', async () => {
  const r = await collect({ token: 'x' }, { fetchEntries: async () => { const e = new Error('a'); e.name = 'AbortError'; throw e; } });
  assert.equal(r.status, 'DOWN');
  assert.equal(r.errorCode, 'TIMEOUT');
});

test('TEST 13: auth absent → UNKNOWN/NOT_CONFIGURED (not a function outage)', async () => {
  delete process.env[ENV];
  const r = await collect({});
  assert.equal(r.status, 'UNKNOWN');
  assert.equal(r.errorCode, 'NOT_CONFIGURED');
});

test('TEST 14: 403 permission denied → collector GCP_PERMISSION_DENIED (not function DOWN)', async () => {
  const r = await collect({ token: 'x' }, { fetchEntries: async () => ({ auth: 'FAILED', entries: null }) });
  assert.equal(r.status, 'DOWN');
  assert.equal(r.errorCode, 'GCP_PERMISSION_DENIED');
});

test('TEST 15: raw Cloud Logging payload is NEVER persisted', () => {
  const e = normalizeLogEntry(entry({ severity: 'ERROR', textPayload: 'RAW-SENSITIVE-BODY', jsonPayload: { message: 'RAW-JSON-BODY', body: 'feedback text here' } }));
  const s = JSON.stringify(e);
  assert.ok(!s.includes('RAW-SENSITIVE-BODY') && !s.includes('RAW-JSON-BODY') && !s.includes('feedback text here'), 'raw payload persisted');
});

test('classifyGcp: severity → event type mapping', () => {
  assert.equal(classifyGcp({ severity: 'WARNING', textPayload: 'x' }).eventType, 'gcp.function.warning');
  assert.equal(classifyGcp({ severity: 'INFO' }).eventType, 'gcp.function.execution');
  assert.equal(classifyGcp({ severity: 'ERROR', textPayload: 'permission denied' }).errorCode, 'FUNCTION_PERMISSION_DENIED');
});
