// IAP core tests. Pure logic (allow-list, provider parsing, idempotency key)
// runs anywhere; grantCredit + attack chains need the Firestore emulator.
// Run: cd functions && npm run build && cd .. && \
//   firebase emulators:exec --only firestore "node --test functions/test/iap-core.test.mjs"
import { test, before, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  creditForProduct,
  idempotencyKey,
  grantCredit,
  parseAppleReceipt,
  parseGooglePurchase,
} from '../lib/iap-core.js';

const HAS_EMU = !!process.env.FIRESTORE_EMULATOR_HOST;

describe('iap-core pure logic (allow-list, idempotency key = store-authoritative only)', () => {
  test('creditForProduct: allow-list only — unknown product grants nothing', () => {
    assert.equal(creditForProduct('premium_link_single_v2'), 1); // new purchase product
    assert.equal(creditForProduct('premium_link_single'), 1);    // legacy recovery product
    assert.equal(creditForProduct('bogus'), null);
    assert.equal(creditForProduct(''), null);
  });

  test('idempotencyKey: STORE txId only; NEVER a client-controlled value', () => {
    // A present store txId is used verbatim.
    assert.equal(idempotencyKey('ios', 'store-tx', 'RECEIPT'), 'ios:store-tx');
    // No store txId -> deterministic hash of the STORE-verified material.
    const k1 = idempotencyKey('android', undefined, 'TOKEN-XYZ');
    const k2 = idempotencyKey('android', undefined, 'TOKEN-XYZ');
    assert.equal(k1, k2); // deterministic
    assert.ok(k1.startsWith('android:sha256:'));
    // Different store material -> different key.
    assert.notEqual(
      idempotencyKey('android', undefined, 'TOKEN-A'),
      idempotencyKey('android', undefined, 'TOKEN-B'),
    );
    // Empty / whitespace store txId falls back to the hash, not to anything else.
    assert.equal(idempotencyKey('ios', '   ', 'RCPT'), idempotencyKey('ios', undefined, 'RCPT'));
    assert.equal(idempotencyKey('ios', null, 'RCPT'), idempotencyKey('ios', undefined, 'RCPT'));
  });
});

describe('parseAppleReceipt — product-bound, store transactionId, failure states', () => {
  const appleOk = (txid, pid = 'premium_link_single') => ({
    status: 0,
    receipt: { in_app: [{ product_id: pid, transaction_id: txid, purchase_date_ms: '100' }] },
  });

  test('valid receipt + matching product -> VERIFIED with STORE transactionId', () => {
    const r = parseAppleReceipt(appleOk('APPLE-TX-1'), 'premium_link_single');
    assert.equal(r.ok, true);
    assert.equal(r.transactionId, 'APPLE-TX-1');
  });

  test('newest matching transaction is chosen', () => {
    const json = {
      status: 0,
      receipt: {
        in_app: [
          { product_id: 'premium_link_single', transaction_id: 'OLD', purchase_date_ms: '100' },
          { product_id: 'premium_link_single', transaction_id: 'NEW', purchase_date_ms: '200' },
        ],
      },
    };
    assert.equal(parseAppleReceipt(json, 'premium_link_single').transactionId, 'NEW');
  });

  test('wrong product in receipt -> REJECT (product mismatch, permanent)', () => {
    const r = parseAppleReceipt(appleOk('X', 'some_other_product'), 'premium_link_single');
    assert.equal(r.ok, false);
    assert.equal(r.transient, false);
  });

  test('non-zero permanent status -> REJECT permanent', () => {
    const r = parseAppleReceipt({ status: 21002 }, 'premium_link_single');
    assert.equal(r.ok, false);
    assert.equal(r.transient, false);
  });

  test('transient Apple statuses (21004/21005/21009/21100) -> REJECT but transient', () => {
    for (const s of [21004, 21005, 21009, 21100]) {
      assert.equal(parseAppleReceipt({ status: s }, 'premium_link_single').transient, true, `status ${s}`);
    }
  });

  test('missing store transaction_id -> REJECT (never coerced to a client/undefined value)', () => {
    const json = {
      status: 0,
      receipt: { in_app: [{ product_id: 'premium_link_single', purchase_date_ms: '1' }] },
    };
    const r = parseAppleReceipt(json, 'premium_link_single');
    assert.equal(r.ok, false);
    assert.equal(r.reason, 'apple_no_transaction_id');
  });

  test('malformed / empty response -> REJECT', () => {
    assert.equal(parseAppleReceipt({}, 'premium_link_single').ok, false);
    assert.equal(parseAppleReceipt(null, 'premium_link_single').ok, false);
  });
});

describe('parseGooglePurchase — purchase state + store identity', () => {
  test('purchased (state 0) + orderId -> VERIFIED store identity', () => {
    const r = parseGooglePurchase({ purchaseState: 0, orderId: 'GPA.1' }, 'TOKEN');
    assert.equal(r.ok, true);
    assert.equal(r.transactionId, 'GPA.1');
  });

  test('no orderId -> falls back to the store-verified purchaseToken (still store material)', () => {
    const r = parseGooglePurchase({ purchaseState: 0 }, 'TOKEN-XYZ');
    assert.equal(r.ok, true);
    assert.equal(r.transactionId, 'TOKEN-XYZ');
  });

  test('cancelled (state 1) -> REJECT permanent', () => {
    const r = parseGooglePurchase({ purchaseState: 1, orderId: 'X' }, 'T');
    assert.equal(r.ok, false);
    assert.equal(r.transient, false);
  });

  test('pending (state 2) -> REJECT transient (no credit yet)', () => {
    assert.equal(parseGooglePurchase({ purchaseState: 2 }, 'T').transient, true);
  });

  test('malformed / empty response -> REJECT', () => {
    assert.equal(parseGooglePurchase(null, 'T').ok, false);
    assert.equal(parseGooglePurchase(undefined, 'T').ok, false);
  });
});

describe('iap-core grantCredit + REPLAY ATTACK — idempotent atomic grant (Firestore emulator)',
  { skip: !HAS_EMU ? 'FIRESTORE_EMULATOR_HOST not set' : false }, () => {
  let db;
  before(async () => {
    const { initializeApp } = await import('firebase-admin/app');
    const { getFirestore } = await import('firebase-admin/firestore');
    initializeApp({ projectId: 'demo-iap-test' });
    db = getFirestore();
  });

  const P = (uid, key) => ({ uid, key, platform: 'ios', productId: 'premium_link_single', credit: 1 });
  const creditsOf = async (uid) => (await db.collection('users').doc(uid).get()).get('paidLinkCredits');

  test('valid grant → +1', async () => {
    const uid = 'u-valid';
    const r = await grantCredit(db, P(uid, 'ios:tx-valid'));
    assert.equal(r.granted, true);
    assert.equal(r.credits, 1);
    assert.equal(await creditsOf(uid), 1);
  });

  test('duplicate (same key) → +0 (idempotent, replay-safe)', async () => {
    const uid = 'u-dup';
    const r1 = await grantCredit(db, P(uid, 'ios:tx-dup'));
    const r2 = await grantCredit(db, P(uid, 'ios:tx-dup'));
    assert.equal(r1.granted, true);
    assert.equal(r2.granted, false);
    assert.equal(r2.alreadyProcessed, true);
    assert.equal(await creditsOf(uid), 1); // not 2
  });

  test('two concurrent identical verifies → total +1', async () => {
    const uid = 'u-conc';
    const res = await Promise.allSettled([
      grantCredit(db, P(uid, 'ios:tx-conc')),
      grantCredit(db, P(uid, 'ios:tx-conc')),
    ]);
    const granted = res.filter((r) => r.status === 'fulfilled' && r.value.granted).length;
    assert.equal(granted, 1); // exactly one grants
    assert.equal(await creditsOf(uid), 1);
  });

  test('two different transactions for same user → +2 (distinct purchases)', async () => {
    const uid = 'u-two';
    await grantCredit(db, P(uid, 'ios:tx-a'));
    await grantCredit(db, P(uid, 'ios:tx-b'));
    assert.equal(await creditsOf(uid), 2);
  });

  // ---- REPLAY ATTACK: same verified purchase, attacker varies client txId ----

  test('REPLAY ATTACK (Apple orderId present): same purchase, client txId A/B/random → total +1', async () => {
    const uid = 'u-replay-apple';
    const storeTx = 'STORE-TX-REPLAY'; // store-authoritative, identical across attempts
    for (const clientTx of ['A', 'B', 'zzz-random-9182']) {
      // The client txId is not even an input to the key — proving it cannot influence dedupe.
      const key = idempotencyKey('ios', storeTx, 'RECEIPT-SAME');
      await grantCredit(db, {
        uid, key, platform: 'ios', productId: 'premium_link_single', credit: 1, clientTransactionId: clientTx,
      });
    }
    assert.equal(await creditsOf(uid), 1); // exactly one credit despite 3 different client txIds
  });

  test('REPLAY ATTACK (Google, no orderId): same purchaseToken hash → total +1 across client txIds', async () => {
    const uid = 'u-replay-google';
    const token = 'PURCHASE-TOKEN-NO-ORDERID';
    for (const clientTx of ['A', 'B', 'C']) {
      const key = idempotencyKey('android', undefined, token); // deterministic hash of store token
      await grantCredit(db, {
        uid, key, platform: 'android', productId: 'premium_link_single', credit: 1, clientTransactionId: clientTx,
      });
    }
    assert.equal(await creditsOf(uid), 1);
  });

  // ---- FULL E2E: provider parse → store identity → key → grant ----

  test('E2E Apple: parse → key → grant, replay with different client txId → +1', async () => {
    const uid = 'u-e2e-apple';
    const appleJson = {
      status: 0,
      receipt: { in_app: [{ product_id: 'premium_link_single', transaction_id: 'E2E-APPLE-TX', purchase_date_ms: '1' }] },
    };
    for (const clientTx of ['A', 'B']) {
      const vr = parseAppleReceipt(appleJson, 'premium_link_single');
      assert.equal(vr.ok, true);
      const key = idempotencyKey('ios', vr.transactionId, 'RECEIPT');
      await grantCredit(db, {
        uid, key, platform: 'ios', productId: 'premium_link_single', credit: 1, clientTransactionId: clientTx,
      });
    }
    assert.equal(await creditsOf(uid), 1);
  });

  test('E2E Google: parse → key → grant, replay → +1', async () => {
    const uid = 'u-e2e-google';
    const gJson = { purchaseState: 0, orderId: 'GPA.E2E' };
    for (const clientTx of ['A', 'B']) {
      const vr = parseGooglePurchase(gJson, 'TOKEN');
      assert.equal(vr.ok, true);
      const key = idempotencyKey('android', vr.transactionId, 'TOKEN');
      await grantCredit(db, {
        uid, key, platform: 'android', productId: 'premium_link_single', credit: 1, clientTransactionId: clientTx,
      });
    }
    assert.equal(await creditsOf(uid), 1);
  });
});
