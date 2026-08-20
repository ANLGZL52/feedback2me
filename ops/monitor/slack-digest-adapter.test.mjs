// Observability V7 — Slack digest adapter tests. MOCKED HTTP only — NEVER hits Slack,
// NEVER uses a real webhook. Run: node --test ops/monitor/slack-digest-adapter.test.mjs
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { slackDigestAdapter } from './slack-digest-adapter.mjs';

const FAKE = 'https://hooks.slack.test/services/AAA/BBB/secret-token-xyz'; // fake, test-only
const res = (status, headers = {}) => ({ status, headers: { get: (k) => headers[k.toLowerCase()] ?? null } });
// A fetch mock that records calls and returns a scripted sequence of responses/throws.
const mockFetch = (script) => { let i = 0; const calls = []; const fn = async (url, opts) => { calls.push({ url, opts }); const step = script[Math.min(i, script.length - 1)]; i++; if (step.throw) { const e = new Error(step.throw); e.name = step.name || 'Error'; throw e; } return res(step.status, step.headers); }; fn.calls = calls; return fn; };
const clock = () => { let t = 1000; return () => (t += 5); };

describe('slack adapter configuration', () => {
  test('empty webhook -> not configured, never calls fetch', async () => {
    const f = mockFetch([{ status: 200 }]);
    const a = slackDigestAdapter('', { fetchImpl: f });
    assert.equal(a.configured, false);
    const r = await a.send('hi');
    assert.equal(r.ok, false); assert.equal(f.calls.length, 0);
  });
  test('present webhook -> configured, name=slack', () => {
    assert.equal(slackDigestAdapter(FAKE).configured, true);
    assert.equal(slackDigestAdapter(FAKE).name, 'slack');
  });
});

describe('slack adapter HTTP semantics (mocked)', () => {
  test('200 -> ok, one call, returns status + latency', async () => {
    const f = mockFetch([{ status: 200 }]);
    const r = await slackDigestAdapter(FAKE, { fetchImpl: f, clock: clock() }).send('digest');
    assert.equal(r.ok, true); assert.equal(r.status, 200); assert.equal(f.calls.length, 1);
    assert.ok(typeof r.latencyMs === 'number');
  });
  test('POST application/json with {text} body', async () => {
    const f = mockFetch([{ status: 200 }]);
    await slackDigestAdapter(FAKE, { fetchImpl: f }).send('hello world');
    assert.equal(f.calls[0].opts.method, 'POST');
    assert.equal(f.calls[0].opts.headers['Content-Type'], 'application/json');
    assert.deepEqual(JSON.parse(f.calls[0].opts.body), { text: 'hello world' });
  });
  test('429 -> ONE bounded retry then result', async () => {
    const f = mockFetch([{ status: 429, headers: { 'retry-after': '0' } }, { status: 200 }]);
    const r = await slackDigestAdapter(FAKE, { fetchImpl: f, clock: clock() }).send('d');
    assert.equal(r.ok, true); assert.equal(f.calls.length, 2);
  });
  test('500 -> ONE retry; still 500 -> fail (2 calls max)', async () => {
    const f = mockFetch([{ status: 500 }, { status: 500 }]);
    const r = await slackDigestAdapter(FAKE, { fetchImpl: f, clock: clock() }).send('d');
    assert.equal(r.ok, false); assert.equal(r.status, 500); assert.equal(f.calls.length, 2);
  });
  test('timeout (abort) -> retry once, still fails -> status timeout', async () => {
    const f = mockFetch([{ throw: 'aborted', name: 'AbortError' }, { throw: 'aborted', name: 'AbortError' }]);
    const r = await slackDigestAdapter(FAKE, { fetchImpl: f, clock: clock(), timeoutMs: 50 }).send('d');
    assert.equal(r.ok, false); assert.equal(r.status, 'timeout'); assert.equal(f.calls.length, 2);
  });
  test('network error (non-abort throw) -> ONE retry, status network_error', async () => {
    const f = mockFetch([{ throw: 'ECONNRESET', name: 'Error' }, { throw: 'ECONNRESET', name: 'Error' }]);
    const r = await slackDigestAdapter(FAKE, { fetchImpl: f, clock: clock() }).send('d');
    assert.equal(r.ok, false); assert.equal(r.status, 'network_error'); assert.equal(f.calls.length, 2);
    assert.ok(!JSON.stringify(r).includes('secret-token-xyz'), 'network-error result must not leak the webhook');
  });
  test('transient network error then 200 -> recovers within the retry budget', async () => {
    const f = mockFetch([{ throw: 'ECONNRESET', name: 'Error' }, { status: 200 }]);
    const r = await slackDigestAdapter(FAKE, { fetchImpl: f, clock: clock() }).send('d');
    assert.equal(r.ok, true); assert.equal(r.status, 200); assert.equal(f.calls.length, 2);
  });
  test('400 -> NO retry (1 call)', async () => {
    const f = mockFetch([{ status: 400 }, { status: 200 }]);
    const r = await slackDigestAdapter(FAKE, { fetchImpl: f }).send('d');
    assert.equal(r.ok, false); assert.equal(r.status, 400); assert.equal(f.calls.length, 1);
  });
  test('401 -> NO retry', async () => {
    const f = mockFetch([{ status: 401 }, { status: 200 }]);
    const r = await slackDigestAdapter(FAKE, { fetchImpl: f }).send('d');
    assert.equal(r.ok, false); assert.equal(r.status, 401); assert.equal(f.calls.length, 1);
  });
  test('403 -> NO retry', async () => {
    const f = mockFetch([{ status: 403 }, { status: 200 }]);
    const r = await slackDigestAdapter(FAKE, { fetchImpl: f }).send('d');
    assert.equal(r.status, 403); assert.equal(f.calls.length, 1);
  });
});

describe('slack adapter secret safety', () => {
  test('result NEVER contains the webhook URL', async () => {
    const f = mockFetch([{ status: 200 }]);
    const r = await slackDigestAdapter(FAKE, { fetchImpl: f }).send('d');
    const s = JSON.stringify(r);
    assert.ok(!s.includes(FAKE) && !s.includes('secret-token-xyz'), 'adapter result must not leak the webhook');
  });
  test('result shape is safe {ok,status,latencyMs} only', async () => {
    const f = mockFetch([{ status: 200 }]);
    const r = await slackDigestAdapter(FAKE, { fetchImpl: f }).send('d');
    assert.deepEqual(Object.keys(r).sort(), ['latencyMs', 'ok', 'status']);
  });
});
