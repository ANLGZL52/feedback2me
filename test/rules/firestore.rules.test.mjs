// Firestore Security Rules — feedback lifecycle + entitlement invariant testleri.
// ÇALIŞTIRMA (Java + Firestore emulator gerekir):
//   cd test/rules && npm install
//   cd ../.. && firebase emulators:exec --only firestore "node --test test/rules"
//
// Kapsam (§11): Demo/Premium ALLOW/DENY; createdAt-anchored strict duration
// (server-authoritative, sıfır tolerans); premium credit atomic consume;
// demo entitlement; owner reactivation; validUntil/createdAt immutability.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc,
  setDoc,
  updateDoc,
  writeBatch,
  serverTimestamp,
  increment,
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = 'feedbacktome-rules-test';
const __dirname = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(__dirname, '..', '..', 'firestore.rules'), 'utf8');

const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const TEXT = 'Bu yeterince uzun bir geri bildirim metni.'; // >= 10

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules, host: '127.0.0.1', port: 8080 },
  });
});
after(async () => await testEnv.cleanup());
beforeEach(async () => await testEnv.clearFirestore());

async function seedLink(id, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'links', id), {
      ownerId: 'owner1',
      code: id,
      linkTier: 'demo',
      isActive: true,
      demoSubmissionUsed: false,
      createdAt: Timestamp.fromMillis(Date.now() - MIN), // aktif: 1 dk önce
      validUntil: Timestamp.fromMillis(Date.now() + 5 * MIN),
      ...data,
    });
  });
}

async function seedUser(uid, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', uid), {
      paidLinkCredits: 0,
      isPremium: false,
      freeDemoLinkUsed: false,
      ...data,
    });
  });
}

const guestDb = () => testEnv.unauthenticatedContext().firestore();
const ownerDb = () => testEnv.authenticatedContext('owner1').firestore();

/** Demo başarılı akışı: feedback + link consume AYNI batch. */
function demoConsumeBatch(db, linkId, fbId = 'fb1') {
  const b = writeBatch(db);
  b.set(doc(db, 'feedbacks', fbId), { linkId, textRaw: TEXT });
  b.update(doc(db, 'links', linkId), { demoSubmissionUsed: true, isActive: false });
  return b.commit();
}

/** Create batch: link + (opsiyonel) user entitlement yazımı. */
function createLinkBatch(db, { id, tier, createdAt, userWrite }) {
  const b = writeBatch(db);
  b.set(doc(db, 'links', id), {
    ownerId: 'owner1',
    code: id,
    linkTier: tier,
    createdAt: createdAt ?? serverTimestamp(),
    isActive: true,
    demoSubmissionUsed: false,
    validUntil: Timestamp.fromMillis(Date.now() + (tier === 'demo' ? 10 * MIN : 24 * HOUR)),
  });
  if (userWrite) userWrite(b, db); // aynı firestore instance'ı geç
  return b.commit();
}

describe('DEMO', () => {
  it('1) normal Demo create (serverTimestamp + freeDemoLinkUsed false→true) → ALLOW', async () => {
    await seedUser('owner1', { freeDemoLinkUsed: false });
    await assertSucceeds(
      createLinkBatch(ownerDb(), {
        id: 'd1',
        tier: 'demo',
        userWrite: (b, db) =>
          b.set(doc(db, 'users', 'owner1'), { freeDemoLinkUsed: true }, { merge: true }),
      }),
    );
  });

  it('1b) fresh user (doc yok) ilk Demo create → ALLOW', async () => {
    await assertSucceeds(
      createLinkBatch(ownerDb(), {
        id: 'd1b',
        tier: 'demo',
        userWrite: (b, db) =>
          b.set(doc(db, 'users', 'owner1'), { freeDemoLinkUsed: true }, { merge: true }),
      }),
    );
  });

  it('2) Demo create postdated createdAt (!= request.time) → DENY (süre uzatma)', async () => {
    await seedUser('owner1', { freeDemoLinkUsed: false });
    await assertFails(
      createLinkBatch(ownerDb(), {
        id: 'd2',
        tier: 'demo',
        createdAt: Timestamp.fromMillis(Date.now() + 60 * MIN), // sunucu saatine eşit değil
        userWrite: (b, db) =>
          b.set(doc(db, 'users', 'owner1'), { freeDemoLinkUsed: true }, { merge: true }),
      }),
    );
  });

  it('3) first feedback + atomic demo consume → ALLOW', async () => {
    await seedLink('d3', { linkTier: 'demo' });
    await assertSucceeds(demoConsumeBatch(guestDb(), 'd3'));
  });

  it('4) yalnız feedback create (link kapatılmaz) → DENY', async () => {
    await seedLink('d4', { linkTier: 'demo' });
    await assertFails(
      setDoc(doc(guestDb(), 'feedbacks', 'fb4'), { linkId: 'd4', textRaw: TEXT }),
    );
  });

  it('5) second Demo feedback (used) → DENY', async () => {
    await seedLink('d5', { linkTier: 'demo', demoSubmissionUsed: true, isActive: false });
    await assertFails(demoConsumeBatch(guestDb(), 'd5'));
  });

  it('6) expired Demo (createdAt 11 dk önce) → DENY', async () => {
    await seedLink('d6', {
      linkTier: 'demo',
      createdAt: Timestamp.fromMillis(Date.now() - 11 * MIN),
    });
    await assertFails(demoConsumeBatch(guestDb(), 'd6'));
  });

  it('7) owner consumed Demo reactivate (isActive false→true) → DENY', async () => {
    await seedLink('d7', { linkTier: 'demo', demoSubmissionUsed: true, isActive: false });
    await assertFails(updateDoc(doc(ownerDb(), 'links', 'd7'), { isActive: true }));
  });

  it('8) owner demoSubmissionUsed true→false → DENY', async () => {
    await seedLink('d8', { linkTier: 'demo', demoSubmissionUsed: true, isActive: false });
    await assertFails(updateDoc(doc(ownerDb(), 'links', 'd8'), { demoSubmissionUsed: false }));
  });

  it('9) ikinci ücretsiz Demo (freeDemoLinkUsed zaten true) → DENY', async () => {
    await seedUser('owner1', { freeDemoLinkUsed: true });
    await assertFails(
      createLinkBatch(ownerDb(), {
        id: 'd9',
        tier: 'demo',
        userWrite: (b, db) =>
          b.set(doc(db, 'users', 'owner1'), { freeDemoLinkUsed: true }, { merge: true }),
      }),
    );
  });
});

describe('PREMIUM', () => {
  it('10) credit>=1 + atomic decrement + Premium create → ALLOW', async () => {
    await seedUser('owner1', { paidLinkCredits: 2, freeDemoLinkUsed: true });
    await assertSucceeds(
      createLinkBatch(ownerDb(), {
        id: 'p10',
        tier: 'premium',
        userWrite: (b, db) =>
          b.update(doc(db, 'users', 'owner1'), { paidLinkCredits: increment(-1) }),
      }),
    );
  });

  it('10b) aktif abonelik (isPremium) + kredi sabit + Premium create → ALLOW', async () => {
    await seedUser('owner1', { isPremium: true, paidLinkCredits: 0, freeDemoLinkUsed: true });
    await assertSucceeds(
      createLinkBatch(ownerDb(), { id: 'p10b', tier: 'premium' }),
    );
  });

  it('11) Premium create ama credit decrement YOK → DENY', async () => {
    await seedUser('owner1', { paidLinkCredits: 2, freeDemoLinkUsed: true });
    await assertFails(createLinkBatch(ownerDb(), { id: 'p11', tier: 'premium' }));
  });

  it('12) credit=0 + Premium create → DENY', async () => {
    await seedUser('owner1', { paidLinkCredits: 0, freeDemoLinkUsed: true });
    await assertFails(
      createLinkBatch(ownerDb(), {
        id: 'p12',
        tier: 'premium',
        userWrite: (b, db) =>
          b.update(doc(db, 'users', 'owner1'), { paidLinkCredits: increment(-1) }),
      }),
    );
  });

  it('13) credit decrement yanlış miktar (-2) → DENY', async () => {
    await seedUser('owner1', { paidLinkCredits: 3, freeDemoLinkUsed: true });
    await assertFails(
      createLinkBatch(ownerDb(), {
        id: 'p13',
        tier: 'premium',
        userWrite: (b, db) =>
          b.update(doc(db, 'users', 'owner1'), { paidLinkCredits: increment(-2) }),
      }),
    );
  });

  it('14) Premium create postdated createdAt (>24h uzatma) → DENY', async () => {
    await seedUser('owner1', { paidLinkCredits: 2, freeDemoLinkUsed: true });
    await assertFails(
      createLinkBatch(ownerDb(), {
        id: 'p14',
        tier: 'premium',
        createdAt: Timestamp.fromMillis(Date.now() + 40 * HOUR),
        userWrite: (b, db) =>
          b.update(doc(db, 'users', 'owner1'), { paidLinkCredits: increment(-1) }),
      }),
    );
  });

  it('15) active Premium feedback → ALLOW', async () => {
    await seedLink('p15', {
      linkTier: 'premium',
      createdAt: Timestamp.fromMillis(Date.now() - HOUR),
    });
    await assertSucceeds(
      setDoc(doc(guestDb(), 'feedbacks', 'pf15'), { linkId: 'p15', textRaw: TEXT }),
    );
  });

  it('15b) Premium çoklu feedback (global kapanmaz) → ALLOW', async () => {
    await seedLink('p15b', {
      linkTier: 'premium',
      createdAt: Timestamp.fromMillis(Date.now() - HOUR),
    });
    await assertSucceeds(
      setDoc(doc(guestDb(), 'feedbacks', 'pf15b1'), { linkId: 'p15b', textRaw: TEXT }),
    );
    await assertSucceeds(
      setDoc(doc(guestDb(), 'feedbacks', 'pf15b2'), { linkId: 'p15b', textRaw: TEXT }),
    );
  });

  it('16) expired Premium feedback (createdAt 25h önce) → DENY', async () => {
    await seedLink('p16', {
      linkTier: 'premium',
      createdAt: Timestamp.fromMillis(Date.now() - 25 * HOUR),
    });
    await assertFails(
      setDoc(doc(guestDb(), 'feedbacks', 'pf16'), { linkId: 'p16', textRaw: TEXT }),
    );
  });

  it('17) expired Premium reactivate → DENY', async () => {
    await seedLink('p17', {
      linkTier: 'premium',
      isActive: false,
      createdAt: Timestamp.fromMillis(Date.now() - 25 * HOUR),
    });
    await assertFails(updateDoc(doc(ownerDb(), 'links', 'p17'), { isActive: true }));
  });

  it('18) owner validUntil extension → DENY', async () => {
    await seedLink('p18', {
      linkTier: 'premium',
      createdAt: Timestamp.fromMillis(Date.now() - HOUR),
    });
    await assertFails(
      updateDoc(doc(ownerDb(), 'links', 'p18'), {
        validUntil: Timestamp.fromMillis(Date.now() + 10 * 24 * HOUR),
      }),
    );
  });

  it('18b) owner createdAt değiştirme (expiry anchor) → DENY', async () => {
    await seedLink('p18b', {
      linkTier: 'premium',
      createdAt: Timestamp.fromMillis(Date.now() - HOUR),
    });
    await assertFails(
      updateDoc(doc(ownerDb(), 'links', 'p18b'), {
        createdAt: Timestamp.fromMillis(Date.now() + 10 * HOUR),
      }),
    );
  });
});
