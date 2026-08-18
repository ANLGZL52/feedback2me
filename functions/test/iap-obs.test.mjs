// IAP observability tests — PII-safe structured event contract.
// Pure logic (no network, no emulator): proves buildIapObsEvent emits ONLY
// allow-listed operational fields, correct severity, and that the correlation
// hash never exposes the raw store transaction id.
// Run: cd functions && npm run build && node --test functions/test/iap-obs.test.mjs
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { buildIapObsEvent, safePlatform, txCorrelationHash } from '../lib/iap-core.js';

// The COMPLETE set of keys buildIapObsEvent may ever emit. Anything outside this
// set (receipt, verificationData, transactionId, uid, email, secret, ...) is a leak.
const ALLOWED_KEYS = new Set([
  'source', 'service', 'provider', 'eventType', 'severity', 'platform', 'productId',
  'resultClass', 'latencyMs', 'creditDelta', 'replay', 'errorCode', 'clientRequestId',
  'txCorrelation', 'message',
]);

const FORBIDDEN_SUBSTRINGS = [
  'receipt', 'verification', 'purchasetoken', 'purchase_token', 'sharedsecret',
  'shared_secret', 'authorization', 'bearer', 'idtoken', 'jwt', 'private', 'password', 'email', 'uid',
];

describe('buildIapObsEvent — allow-list only, no PII/secret leakage', () => {
  test('every emitted key is on the allow-list (no accidental fields)', () => {
    const ev = buildIapObsEvent('iap.credit.granted', {
      clientRequestId: 'op-123', platform: 'ios', provider: 'apple',
      productId: 'premium_link_single_v2', resultClass: 'ok', creditDelta: 1, replay: false,
      txCorrelation: 't:abc123', latencyMs: 42,
    });
    for (const k of Object.keys(ev)) assert.ok(ALLOWED_KEYS.has(k), `unexpected key emitted: ${k}`);
  });

  test('sensitive fields passed in are IGNORED (built from allow-list, not spread)', () => {
    // Even if a caller mistakenly passes secrets, buildIapObsEvent must not emit them.
    const ev = buildIapObsEvent('iap.verify.apple.success', {
      clientRequestId: 'op-9', platform: 'ios', provider: 'apple', productId: 'premium_link_single_v2',
      // @ts-ignore intentionally-bogus extra fields
      verificationData: 'BASE64RECEIPT', transactionId: '1000000999', uid: 'firebase-uid-xyz',
      receipt: 'RAW', APPLE_SHARED_SECRET: 'secret', email: 'a@b.com',
    });
    const blob = JSON.stringify(ev).toLowerCase();
    for (const bad of FORBIDDEN_SUBSTRINGS) assert.ok(!blob.includes(bad), `event leaked forbidden token: ${bad} in ${blob}`);
    assert.equal(ev.transactionId, undefined);
    assert.equal(ev.verificationData, undefined);
    assert.equal(ev.uid, undefined);
  });

  test('constant identity fields + severity map', () => {
    const g = buildIapObsEvent('iap.credit.granted', {});
    assert.equal(g.source, 'functions');
    assert.equal(g.service, 'iapVerify');
    assert.equal(g.severity, 'INFO');
    assert.equal(buildIapObsEvent('iap.verify.apple.rejected', {}).severity, 'WARNING');
    assert.equal(buildIapObsEvent('iap.verify.android_disabled', {}).severity, 'WARNING');
    assert.equal(buildIapObsEvent('iap.verify.error', {}).severity, 'ERROR');
  });

  test('missing fields default to null (never undefined/crash)', () => {
    const ev = buildIapObsEvent('iap.verify.started', {});
    assert.equal(ev.provider, null);
    assert.equal(ev.productId, null);
    assert.equal(ev.creditDelta, null);
    assert.equal(ev.replay, null);
    assert.equal(ev.txCorrelation, null);
  });

  test('message embeds eventType + safe errorCode only', () => {
    const ev = buildIapObsEvent('iap.verify.apple.rejected', { errorCode: 'apple_status_21002' });
    assert.equal(ev.message, 'iapVerify iap.verify.apple.rejected apple_status_21002');
    const ok = buildIapObsEvent('iap.verify.started', {});
    assert.equal(ok.message, 'iapVerify iap.verify.started');
  });

  test('creditDelta reflects committed delta semantics', () => {
    assert.equal(buildIapObsEvent('iap.credit.granted', { creditDelta: 1, replay: false }).creditDelta, 1);
    assert.equal(buildIapObsEvent('iap.credit.replay', { creditDelta: 0, replay: true }).creditDelta, 0);
    assert.equal(buildIapObsEvent('iap.credit.replay', { creditDelta: 0, replay: true }).replay, true);
  });
});

describe('safePlatform — sanitize client-supplied platform to a known category', () => {
  test('known platforms pass through', () => {
    for (const p of ['ios', 'apple', 'android', 'google']) assert.equal(safePlatform(p), p);
  });
  test('unknown/garbage collapses to "other" (never echoes arbitrary input)', () => {
    assert.equal(safePlatform('windows'), 'other');
    assert.equal(safePlatform(''), 'other');
    assert.equal(safePlatform('a@b.com'), 'other');
    assert.equal(safePlatform('<script>'), 'other');
  });
});

describe('txCorrelationHash — one-way, never exposes the raw transaction id', () => {
  test('deterministic, truncated, prefixed', () => {
    const k = 'ios:1000000999';
    const h = txCorrelationHash(k);
    assert.equal(h, txCorrelationHash(k)); // deterministic
    assert.ok(h.startsWith('t:'));
    assert.equal(h.length, 2 + 16); // 't:' + 16 hex chars
    assert.ok(!h.includes('1000000999')); // raw tx id NOT present
  });
  test('different keys -> different hashes', () => {
    assert.notEqual(txCorrelationHash('ios:tx-a'), txCorrelationHash('ios:tx-b'));
  });
});
