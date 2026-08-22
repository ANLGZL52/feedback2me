// GCP Cloud Functions log-collector tests. No network (deps.fetchEntries injected).
// Run: node --test ops/monitor/checks/gcp-functions-logs.test.mjs
import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { collect, normalizeLogEntry, classifyGcp, extractOpenAiMeta, extractIapMeta } from './gcp-functions-logs.mjs';

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

// --- aiSummary OpenAI structured-event normalization (safe allow-list) -------
// A cloud_run_revision entry whose jsonPayload is an aiSummary obs event.
const aiEntry = (payload, o = {}) => ({
  timestamp: '2026-08-16T20:08:40Z', severity: 'INFO',
  resource: { type: 'cloud_run_revision', labels: { service_name: 'aisummary', location: 'us-central1', revision_name: 'aisummary-00002-abc' } },
  labels: { 'run.googleapis.com/execution_id': 'exec-oai-1' },
  jsonPayload: payload, ...o,
});
// Real successful production shape (identifiers sanitized).
const successPayload = () => ({
  eventType: 'openai.request.completed', statusClass: '2xx', latencyMs: 2153, openaiProcessingMs: 1665,
  inputTokens: 660, outputTokens: 131, totalTokens: 791, errorCode: null, model: 'gpt-4o-mini',
  provider: 'openai', source: 'functions', service: 'aiSummary',
  clientRequestId: 'client-req-SANITIZED', openaiRequestId: 'req_SANITIZED',
  message: 'aiSummary openai.request.completed',
});

test('OAI success: openai.request.completed → allow-listed metadata preserved', () => {
  const e = normalizeLogEntry(aiEntry(successPayload()));
  assert.equal(e.eventType, 'openai.request.completed');
  assert.equal(e.errorCode, null);
  assert.equal(e.provider, 'openai');
  assert.equal(e.service, 'aisummary');
  assert.deepEqual(e.openai, {
    statusClass: '2xx', model: 'gpt-4o-mini', latencyMs: 2153, openaiProcessingMs: 1665,
    inputTokens: 660, outputTokens: 131, totalTokens: 791,
    openaiRequestId: 'req_SANITIZED', clientRequestId: 'client-req-SANITIZED',
  });
});

test('OAI failure A: OPENAI_AUTH_FAILED (4xx) preserved', () => {
  const e = normalizeLogEntry(aiEntry({ ...successPayload(), eventType: 'openai.request.failed', statusClass: '4xx', errorCode: 'OPENAI_AUTH_FAILED', inputTokens: null, outputTokens: null, totalTokens: null }, { severity: 'ERROR' }));
  assert.equal(e.eventType, 'openai.request.failed');
  assert.equal(e.errorCode, 'OPENAI_AUTH_FAILED');
  assert.equal(e.openai.statusClass, '4xx');
  assert.equal(e.openai.totalTokens, null);
});

test('OAI failure B: OPENAI_RATE_LIMITED (4xx) preserved', () => {
  const e = normalizeLogEntry(aiEntry({ ...successPayload(), eventType: 'openai.request.failed', statusClass: '4xx', errorCode: 'OPENAI_RATE_LIMITED' }, { severity: 'ERROR' }));
  assert.equal(e.errorCode, 'OPENAI_RATE_LIMITED');
});

test('OAI failure C: openai.timeout preserved', () => {
  const e = normalizeLogEntry(aiEntry({ ...successPayload(), eventType: 'openai.timeout', statusClass: 'none', errorCode: 'OPENAI_TIMEOUT' }, { severity: 'ERROR' }));
  assert.equal(e.eventType, 'openai.timeout');
  assert.equal(e.errorCode, 'OPENAI_TIMEOUT');
});

test('OAI PRIVACY: sensitive/unknown fields NEVER survive normalization', () => {
  const dirty = {
    ...successPayload(),
    prompt: 'SENSITIVE_PROMPT_TEXT', completion: 'SENSITIVE_COMPLETION', feedback: 'raw feedback body',
    uid: 'user-uid-123', email: 'jane@example.com', authorization: 'Bearer eyJhbGciSECRET',
    token: 'FIREBASE_ID_TOKEN', OPENAI_API_KEY: 'sk-SECRET-KEY', stack: 'Error at x\n at y',
    extraSecret: 'NESTED', requestBody: { text: 'body' }, responseBody: { choices: [1] },
    nested: { prompt: 'ALSO_SENSITIVE' },
  };
  const e = normalizeLogEntry(aiEntry(dirty));
  const s = JSON.stringify(e);
  for (const bad of ['SENSITIVE_PROMPT_TEXT', 'SENSITIVE_COMPLETION', 'raw feedback body', 'user-uid-123', 'jane@example.com', 'eyJhbGciSECRET', 'FIREBASE_ID_TOKEN', 'sk-SECRET-KEY', 'Error at x', 'NESTED', 'ALSO_SENSITIVE']) {
    assert.ok(!s.includes(bad), `leaked: ${bad}`);
  }
  // Only the allow-listed openai keys exist.
  assert.deepEqual(
    Object.keys(e.openai).sort(),
    ['clientRequestId', 'inputTokens', 'latencyMs', 'model', 'openaiProcessingMs', 'openaiRequestId', 'outputTokens', 'statusClass', 'totalTokens'].sort(),
  );
});

test('OAI malformed numerics → null, never crash', () => {
  const e = normalizeLogEntry(aiEntry({ ...successPayload(), latencyMs: 'abc', totalTokens: {}, inputTokens: null, outputTokens: 131 }));
  assert.equal(e.openai.latencyMs, null);
  assert.equal(e.openai.totalTokens, null);
  assert.equal(e.openai.inputTokens, null);
  assert.equal(e.openai.outputTokens, 131);
});

test('OAI oversized ids are bounded', () => {
  const e = normalizeLogEntry(aiEntry({ ...successPayload(), openaiRequestId: 'r'.repeat(500) }));
  assert.ok(e.openai.openaiRequestId.length <= 64);
});

test('OAI: extractOpenAiMeta reads a JSON string in textPayload too', () => {
  const meta = extractOpenAiMeta({ textPayload: JSON.stringify(successPayload()), resource: { type: 'cloud_run_revision', labels: {} } });
  assert.equal(meta.eventType, 'openai.request.completed');
  assert.equal(meta.metrics.totalTokens, 791);
});

test('OAI guard: non-aiSummary jsonPayload is NOT treated as an OpenAI event', () => {
  assert.equal(extractOpenAiMeta(aiEntry({ eventType: 'openai.request.completed', source: 'other', service: 'x' })), null);
  // A generic entry still normalizes as before (no openai overlay).
  const e = normalizeLogEntry(aiEntry({ message: 'hello', source: 'someservice' }, { severity: 'ERROR', textPayload: 'boom' }));
  assert.equal(e.openai, undefined);
  assert.equal(e.provider, undefined);
  assert.ok(e.eventType.startsWith('gcp.function.'));
});

test('OAI guard: unknown eventType from aiSummary is rejected', () => {
  assert.equal(extractOpenAiMeta(aiEntry({ source: 'functions', service: 'aiSummary', eventType: 'openai.mystery' })), null);
});

// --- iapVerify IAP structured-event normalization (safe allow-list) ---------
// A cloud_run_revision entry whose jsonPayload is an iapVerify obs event.
const iapEntry = (payload, o = {}) => ({
  timestamp: '2026-08-18T15:40:00Z', severity: 'INFO',
  resource: { type: 'cloud_run_revision', labels: { service_name: 'iapverify', location: 'us-central1', revision_name: 'iapverify-00003-xyz' } },
  labels: { 'run.googleapis.com/execution_id': 'exec-iap-1' },
  jsonPayload: payload, ...o,
});
// Real committed-grant shape (built by buildIapObsEvent; identifiers sanitized).
const grantPayload = () => ({
  source: 'functions', service: 'iapVerify', provider: 'apple',
  eventType: 'iap.credit.granted', severity: 'INFO', platform: 'ios',
  productId: 'premium_link_single_v2', resultClass: 'ok', latencyMs: 380,
  creditDelta: 1, replay: false, errorCode: null,
  clientRequestId: 'op-SANITIZED', txCorrelation: 't:abcdef0123456789',
  message: 'iapVerify iap.credit.granted',
});

test('IAP grant: iap.credit.granted → allow-listed metadata preserved', () => {
  const e = normalizeLogEntry(iapEntry(grantPayload()));
  assert.equal(e.eventType, 'iap.credit.granted');
  assert.equal(e.errorCode, null);
  assert.equal(e.provider, 'apple');
  assert.deepEqual(e.iap, {
    platform: 'ios', productId: 'premium_link_single_v2', resultClass: 'ok',
    latencyMs: 380, creditDelta: 1, replay: false,
    clientRequestId: 'op-SANITIZED', txCorrelation: 't:abcdef0123456789',
  });
});

test('IAP replay: creditDelta 0 + replay true preserved', () => {
  const e = normalizeLogEntry(iapEntry({ ...grantPayload(), eventType: 'iap.credit.replay', creditDelta: 0, replay: true }));
  assert.equal(e.eventType, 'iap.credit.replay');
  assert.equal(e.iap.creditDelta, 0);
  assert.equal(e.iap.replay, true);
});

test('IAP rejected: safe reason code surfaced, provider apple', () => {
  const e = normalizeLogEntry(iapEntry({ ...grantPayload(), eventType: 'iap.verify.apple.rejected', errorCode: 'apple_status_21002', creditDelta: 0, resultClass: 'rejected', severity: 'WARNING' }, { severity: 'WARNING' }));
  assert.equal(e.eventType, 'iap.verify.apple.rejected');
  assert.equal(e.errorCode, 'apple_status_21002');
  assert.equal(e.iap.resultClass, 'rejected');
});

test('IAP android.rejected: provider-tagged reject normalized (play_http_401)', () => {
  const e = normalizeLogEntry(iapEntry({ ...grantPayload(), eventType: 'iap.verify.android.rejected', provider: 'android', platform: 'android', errorCode: 'play_http_401', creditDelta: 0, resultClass: 'rejected', severity: 'WARNING' }, { severity: 'WARNING' }));
  assert.equal(e.eventType, 'iap.verify.android.rejected');
  assert.equal(e.provider, 'android');
  assert.equal(e.errorCode, 'play_http_401');
  assert.equal(e.iap.creditDelta, 0);
});

test('IAP android_disabled: fail-closed event normalized', () => {
  const e = normalizeLogEntry(iapEntry({ ...grantPayload(), eventType: 'iap.verify.android_disabled', provider: 'android', platform: 'android', errorCode: 'ANDROID_VERIFICATION_NOT_CONFIGURED', creditDelta: 0, resultClass: 'disabled' }));
  assert.equal(e.eventType, 'iap.verify.android_disabled');
  assert.equal(e.provider, 'android');
  assert.equal(e.iap.creditDelta, 0);
});

test('IAP: a receipt/verificationData accidentally in payload is NEVER emitted', () => {
  const e = normalizeLogEntry(iapEntry({
    ...grantPayload(),
    // simulate a buggy emitter that leaked sensitive fields into the log payload
    verificationData: 'BASE64-RECEIPT-SECRET', transactionId: '1000000123456', uid: 'firebase-uid-xyz',
    receipt: 'RCPT-SECRET', purchaseToken: 'PT-SECRET',
  }));
  const s = JSON.stringify(e);
  for (const bad of ['BASE64-RECEIPT-SECRET', '1000000123456', 'firebase-uid-xyz', 'RCPT-SECRET', 'PT-SECRET']) {
    assert.ok(!s.includes(bad), `normalizer leaked ${bad}`);
  }
  // The allow-listed iap object must not carry any of those keys.
  assert.equal(e.iap.transactionId, undefined);
  assert.equal(e.iap.verificationData, undefined);
  assert.equal(e.iap.uid, undefined);
});

test('IAP oversized/ malformed fields are bounded & coerced', () => {
  const e = normalizeLogEntry(iapEntry({ ...grantPayload(), clientRequestId: 'x'.repeat(500), latencyMs: 'not-a-number', creditDelta: 'nope' }));
  assert.ok(e.iap.clientRequestId.length <= 64);
  assert.equal(e.iap.latencyMs, null);
  assert.equal(e.iap.creditDelta, null);
});

test('IAP guard: non-iapVerify jsonPayload is NOT treated as an IAP event', () => {
  assert.equal(extractIapMeta(iapEntry({ ...grantPayload(), source: 'other', service: 'x' })), null);
  const e = normalizeLogEntry(iapEntry({ message: 'hello', source: 'someservice' }, { severity: 'ERROR', textPayload: 'boom' }));
  assert.equal(e.iap, undefined);
  assert.ok(e.eventType.startsWith('gcp.function.'));
});

test('IAP guard: unknown eventType from iapVerify is rejected', () => {
  assert.equal(extractIapMeta(iapEntry({ source: 'functions', service: 'iapVerify', eventType: 'iap.mystery' })), null);
});

test('IAP: extractIapMeta reads a JSON string in textPayload too', () => {
  const meta = extractIapMeta({ textPayload: JSON.stringify(grantPayload()), resource: { type: 'cloud_run_revision', labels: {} } });
  assert.equal(meta.eventType, 'iap.credit.granted');
  assert.equal(meta.metrics.creditDelta, 1);
  assert.equal(meta.provider, 'apple');
});
