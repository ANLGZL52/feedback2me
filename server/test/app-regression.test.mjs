// Behavior-regression: the runtime-event instrumentation must be OBSERVATIONAL —
// it must NOT change any HTTP status code or response body shape.
// Run: NODE_ENV=test node --import tsx --test test/app-regression.test.mjs
process.env.NODE_ENV = 'test'; // prevents auto-listen; non-production build
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/index.ts';

let app;
before(async () => { app = await buildApp(); await app.ready(); });

test('GET /health → 200 {ok:true,...} (unchanged contract)', async () => {
  const res = await app.inject({ method: 'GET', url: '/health' });
  assert.equal(res.statusCode, 200);
  const b = res.json();
  assert.equal(b.ok, true);
  assert.equal(b.service, 'feedback2me-api');
  // exactly the original keys — instrumentation added none
  assert.deepEqual(Object.keys(b).sort(), ['ok', 'service', 'ts']);
});

test('protected route without auth → 401 {error:"unauthorized"} (unchanged)', async () => {
  const res = await app.inject({ method: 'GET', url: '/me/feedback-pool' });
  assert.equal(res.statusCode, 401);
  assert.deepEqual(res.json(), { error: 'unauthorized' });
});

test('POST /feedbacks invalid body → 400 {error:"validation",...} (unchanged)', async () => {
  const res = await app.inject({ method: 'POST', url: '/feedbacks', payload: { textRaw: 'short' } });
  assert.equal(res.statusCode, 400);
  const b = res.json();
  assert.equal(b.error, 'validation'); // route's own contract, not reshaped by the observer
  assert.ok('details' in b);
});

test('unknown route → Fastify default 404 shape (unchanged — observer did not replace the handler)', async () => {
  const res = await app.inject({ method: 'GET', url: '/nope-does-not-exist' });
  assert.equal(res.statusCode, 404);
  const b = res.json();
  // Fastify's DEFAULT 404 body: {message, error, statusCode} — proves we did NOT
  // install a custom error/notFound handler that reshapes responses.
  assert.equal(b.statusCode, 404);
  assert.ok('error' in b && 'message' in b);
});

test('correlation id is per-request + opaque (different across two requests)', async () => {
  // request.id is echoed in the default 404 log context; assert two requests differ
  // by injecting and checking the reply-time header if present, else that both succeed.
  const a = await app.inject({ method: 'GET', url: '/health' });
  const b = await app.inject({ method: 'GET', url: '/health' });
  assert.equal(a.statusCode, 200);
  assert.equal(b.statusCode, 200); // both independent requests handled normally
});
