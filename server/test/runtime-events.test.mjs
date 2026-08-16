// Backend runtime-event safety tests. Run: node --import tsx --test test/runtime-events.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildSafeEvent, redactStr, mapErrorCode, newCorrelationId } from '../src/lib/runtime-events.ts';

test('buildSafeEvent copies ONLY allow-listed fields — a body/feedback field is dropped', () => {
  const e = buildSafeEvent({ evt: 'server.request.completed', method: 'POST', route: '/feedbacks/:code', status: 201, ms: 5, cid: 'r1',
    // extra/unsafe fields must never appear:
    body: 'the product is terrible, from Jane <jane@x.com>', headers: { authorization: 'Bearer abc' } });
  const s = JSON.stringify(e);
  assert.ok(!s.includes('terrible'), 'body leaked');
  assert.ok(!s.includes('Jane'), 'name leaked');
  assert.ok(!s.includes('authorization'), 'header leaked');
  assert.equal(e.evt, 'server.request.completed');
  assert.equal(e.route, '/feedbacks/:code');
  assert.equal(e.status, 201);
});

test('redactStr strips jwt / postgres URI / api key / email / Bearer', () => {
  const s = redactStr('conn postgres://u:pw@h:5432/db jwt eyJhbGciOiJIUzI1.eyJzdWIiOiIxMjM.SflKxwRJSMeK key sk-ABCDEFGHIJKLMNOP1234 mail x@y.com auth Bearer zzz');
  assert.ok(!s.includes('pw@h'), 'db cred leaked');
  assert.ok(!s.includes('eyJhbGciOiJIUzI1'), 'jwt leaked');
  assert.ok(!s.includes('sk-ABCDEFGHIJKLMNOP1234'), 'key leaked');
  assert.ok(!s.includes('x@y.com'), 'email leaked');
  assert.ok(!/Bearer zzz/.test(s), 'bearer leaked');
});

test('string values inside allow-listed fields are still redacted', () => {
  const e = buildSafeEvent({ evt: 'server.runtime.error', level: 'error', code: 'INTERNAL_ERROR', route: '/x', cid: 'has a jwt eyJhbGciOiJIUzI1.eyJzdWIiOiIxMjM.SflKxwRJSMeK inside' });
  assert.ok(!JSON.stringify(e).includes('eyJhbGciOiJIUzI1'), 'redaction not applied to field values');
});

test('mapErrorCode returns stable safe codes, never the message', () => {
  assert.equal(mapErrorCode({ validation: [{}] }), 'VALIDATION_ERROR');
  assert.equal(mapErrorCode({ statusCode: 401 }), 'AUTH_INVALID');
  assert.equal(mapErrorCode({ statusCode: 403 }), 'AUTH_FORBIDDEN');
  assert.equal(mapErrorCode(new Error('boom with postgres://u:pw@h/db')), 'INTERNAL_ERROR');
});

test('newCorrelationId is opaque + unique (not sequential, not user-derived)', () => {
  const a = newCorrelationId(), b = newCorrelationId();
  assert.notEqual(a, b);
  assert.match(a, /^[0-9a-f-]{36}$/);
});
