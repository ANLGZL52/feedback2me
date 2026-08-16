// PostgreSQL direct-health probe tests. No real database, no `pg` driver required —
// the client factory (deps.connect) and clock (deps.now) are injected.
// Run: node --test ops/monitor/checks/postgres-direct.test.mjs
import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { check } from './postgres-direct.mjs';

const ENV = 'OPS_POSTGRES_DATABASE_URL';
const SECRET_URI = 'postgres://user:supersecret@db.internal:5432/app?sslmode=require'; // test-only sentinel
afterEach(() => { delete process.env[ENV]; });

// A mock pg client. Records whether end() was called.
function mockClient({ queryImpl, endSpy } = {}) {
  return {
    query: queryImpl || (async () => ({ rows: [{ ok: 1 }] })),
    end: async () => { if (endSpy) endSpy.calls++; },
  };
}
const clock = (a, b) => { let i = 0; const seq = [a, b]; return () => seq[Math.min(i++, 1)]; };

test('TEST 1: credential absent → UNKNOWN / NO_CREDENTIAL (not a Postgres outage)', async () => {
  delete process.env[ENV];
  const r = await check({});
  assert.equal(r.status, 'UNKNOWN');
  assert.equal(r.errorCode, 'NO_CREDENTIAL');
});

test('TEST 2: connect + SELECT 1 succeed within threshold → HEALTHY', async () => {
  process.env[ENV] = SECRET_URI;
  const r = await check({ degradedLatencyMs: 2000 }, { connect: async () => mockClient(), now: clock(0, 84) });
  assert.equal(r.status, 'HEALTHY');
  assert.equal(r.latencyMs, 84);
  assert.equal(r.errorCode, null);
});

test('TEST 3: query ok but latency above threshold → DEGRADED / SLOW', async () => {
  process.env[ENV] = SECRET_URI;
  const r = await check({ degradedLatencyMs: 2000 }, { connect: async () => mockClient(), now: clock(0, 5000) });
  assert.equal(r.status, 'DEGRADED');
  assert.equal(r.errorCode, 'SLOW');
  assert.equal(r.latencyMs, 5000);
});

test('TEST 4: DNS/network failure with credential set → DOWN', async () => {
  process.env[ENV] = SECRET_URI;
  const r = await check({}, { connect: async () => { const e = new Error('getaddrinfo'); e.code = 'ENOTFOUND'; throw e; } });
  assert.equal(r.status, 'DOWN');
  assert.equal(r.errorCode, 'DNS_RESOLUTION_FAILED');
});

test('TEST 5: authentication failure → DOWN / AUTH_FAILED', async () => {
  process.env[ENV] = SECRET_URI;
  const r = await check({}, { connect: async () => { const e = new Error('password authentication failed for user ...'); e.code = '28P01'; throw e; } });
  assert.equal(r.status, 'DOWN');
  assert.equal(r.errorCode, 'AUTH_FAILED');
});

test('TEST 6: query failure (SQLSTATE) → DOWN / QUERY_FAILED', async () => {
  process.env[ENV] = SECRET_URI;
  const r = await check({}, { connect: async () => mockClient({ queryImpl: async () => { const e = new Error('boom'); e.code = '42501'; throw e; } }) });
  assert.equal(r.status, 'DOWN');
  assert.equal(r.errorCode, 'QUERY_FAILED');
});

test('TEST 7: timeout → DOWN / TIMEOUT', async () => {
  process.env[ENV] = SECRET_URI;
  // connect never resolves -> withTimeout fires
  const r = await check({ timeoutMs: 50 }, { connect: () => new Promise(() => {}) });
  assert.equal(r.status, 'DOWN');
  assert.equal(r.errorCode, 'TIMEOUT');
});

test('TEST 8: the raw credential NEVER appears in the serialized result/error', async () => {
  process.env[ENV] = SECRET_URI;
  const results = [];
  results.push(await check({}, { connect: async () => mockClient(), now: clock(0, 10) }));
  results.push(await check({}, { connect: async () => { const e = new Error(SECRET_URI + ' refused'); e.code = 'ECONNREFUSED'; throw e; } }));
  for (const r of results) {
    const s = JSON.stringify(r);
    assert.ok(!s.includes('supersecret'), 'password leaked');
    assert.ok(!s.includes('db.internal'), 'host leaked');
    assert.ok(!s.includes('postgres://'), 'URI leaked');
  }
});

test('TEST 9: client.end() is called after success', async () => {
  process.env[ENV] = SECRET_URI;
  const endSpy = { calls: 0 };
  await check({}, { connect: async () => mockClient({ endSpy }), now: clock(0, 5) });
  assert.equal(endSpy.calls, 1);
});

test('TEST 10: client.end() is called after a post-connect failure', async () => {
  process.env[ENV] = SECRET_URI;
  const endSpy = { calls: 0 };
  await check({}, { connect: async () => mockClient({ endSpy, queryImpl: async () => { const e = new Error('x'); e.code = '42501'; throw e; } }) });
  assert.equal(endSpy.calls, 1);
});

test('TEST 11: driver unavailable (secret set, pg not installed) → UNKNOWN / DRIVER_UNAVAILABLE (not DOWN)', async () => {
  process.env[ENV] = SECRET_URI;
  const r = await check({}, { connect: async () => { const e = new Error('driver'); e.code = 'OPS_DRIVER'; throw e; } });
  assert.equal(r.status, 'UNKNOWN');
  assert.equal(r.errorCode, 'DRIVER_UNAVAILABLE');
});
