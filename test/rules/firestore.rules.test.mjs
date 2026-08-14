// Firestore Security Rules — feedback lifecycle invariant testleri.
// ÇALIŞTIRMA (Java + Firestore emulator gerekir; CI'da mevcut olur):
//   cd test/rules && npm install
//   cd ../.. && firebase emulators:exec --only firestore "node --test test/rules"
//
// Kapsam (§6): Demo ALLOW/DENY (atomic consume + used + expired + cap),
// Premium ALLOW/DENY (expired + cap + normal), Owner reactivation DENY.

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
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = 'feedbacktome-rules-test';
const __dirname = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(__dirname, '..', '..', 'firestore.rules'), 'utf8');

const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const TEXT = 'Bu yeterince uzun bir geri bildirim metni.'; // >= 10

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules, host: '127.0.0.1', port: 8080 },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

/** Kuralları bypass ederek veri tohumla. */
async function seedLink(id, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'links', id), {
      ownerId: 'owner1',
      code: id,
      linkTier: 'demo',
      isActive: true,
      demoSubmissionUsed: false,
      validUntil: Timestamp.fromMillis(Date.now() + 5 * MIN),
      ...data,
    });
  });
}

const guestDb = () => testEnv.unauthenticatedContext().firestore();
const userDb = (uid = 'owner1') => testEnv.authenticatedContext(uid).firestore();

/** Demo başarılı akışı: feedback + link consume AYNI batch. */
function demoConsumeBatch(db, linkId, fbId = 'fb1') {
  const b = writeBatch(db);
  b.set(doc(db, 'feedbacks', fbId), { linkId, textRaw: TEXT });
  b.update(doc(db, 'links', linkId), { demoSubmissionUsed: true, isActive: false });
  return b.commit();
}

describe('DEMO', () => {
  it('1) active demo + feedback + atomic consume batch → ALLOW', async () => {
    await seedLink('d1', { linkTier: 'demo' });
    await assertSucceeds(demoConsumeBatch(guestDb(), 'd1'));
  });

  it('2) active demo + YALNIZ feedback create (link kapatılmaz) → DENY', async () => {
    await seedLink('d2', { linkTier: 'demo' });
    await assertFails(
      setDoc(doc(guestDb(), 'feedbacks', 'fb2'), { linkId: 'd2', textRaw: TEXT }),
    );
  });

  it('3) demo already used + feedback → DENY', async () => {
    await seedLink('d3', { linkTier: 'demo', demoSubmissionUsed: true, isActive: false });
    await assertFails(demoConsumeBatch(guestDb(), 'd3'));
  });

  it('4) expired demo → DENY', async () => {
    await seedLink('d4', {
      linkTier: 'demo',
      validUntil: Timestamp.fromMillis(Date.now() - MIN),
    });
    await assertFails(demoConsumeBatch(guestDb(), 'd4'));
  });

  it('5) demo create validUntil > cap (20 dk) → DENY', async () => {
    await assertFails(
      setDoc(doc(userDb(), 'links', 'dc1'), {
        ownerId: 'owner1',
        code: 'dc1',
        linkTier: 'demo',
        isActive: true,
        demoSubmissionUsed: false,
        validUntil: Timestamp.fromMillis(Date.now() + 20 * MIN),
      }),
    );
  });

  it('10) normal 10 dk demo create → ALLOW', async () => {
    await assertSucceeds(
      setDoc(doc(userDb(), 'links', 'dc2'), {
        ownerId: 'owner1',
        code: 'dc2',
        linkTier: 'demo',
        isActive: true,
        demoSubmissionUsed: false,
        validUntil: Timestamp.fromMillis(Date.now() + 10 * MIN),
      }),
    );
  });
});

describe('PREMIUM', () => {
  it('6) active premium feedback (link update yok) → ALLOW', async () => {
    await seedLink('p1', {
      linkTier: 'premium',
      validUntil: Timestamp.fromMillis(Date.now() + HOUR),
    });
    await assertSucceeds(
      setDoc(doc(guestDb(), 'feedbacks', 'pf1'), { linkId: 'p1', textRaw: TEXT }),
    );
  });

  it('6b) premium çoklu feedback → ALLOW (global kapanmaz)', async () => {
    await seedLink('p1b', {
      linkTier: 'premium',
      validUntil: Timestamp.fromMillis(Date.now() + HOUR),
    });
    await assertSucceeds(
      setDoc(doc(guestDb(), 'feedbacks', 'pf1b'), { linkId: 'p1b', textRaw: TEXT }),
    );
    await assertSucceeds(
      setDoc(doc(guestDb(), 'feedbacks', 'pf2b'), { linkId: 'p1b', textRaw: TEXT }),
    );
  });

  it('7) expired premium feedback → DENY', async () => {
    await seedLink('p2', {
      linkTier: 'premium',
      validUntil: Timestamp.fromMillis(Date.now() - MIN),
    });
    await assertFails(
      setDoc(doc(guestDb(), 'feedbacks', 'pf3'), { linkId: 'p2', textRaw: TEXT }),
    );
  });

  it('8) premium create validUntil > cap (30 gün) → DENY', async () => {
    await assertFails(
      setDoc(doc(userDb(), 'links', 'pc1'), {
        ownerId: 'owner1',
        code: 'pc1',
        linkTier: 'premium',
        isActive: true,
        demoSubmissionUsed: false,
        validUntil: Timestamp.fromMillis(Date.now() + 30 * DAY),
      }),
    );
  });

  it('9) normal 24 saat premium create → ALLOW', async () => {
    await assertSucceeds(
      setDoc(doc(userDb(), 'links', 'pc2'), {
        ownerId: 'owner1',
        code: 'pc2',
        linkTier: 'premium',
        isActive: true,
        demoSubmissionUsed: false,
        validUntil: Timestamp.fromMillis(Date.now() + 24 * HOUR),
      }),
    );
  });
});

describe('OWNER lifecycle immutability', () => {
  it('11) owner consumed demo\'yu reactivate (isActive false→true) → DENY', async () => {
    await seedLink('o1', { linkTier: 'demo', demoSubmissionUsed: true, isActive: false });
    await assertFails(updateDoc(doc(userDb(), 'links', 'o1'), { isActive: true }));
  });

  it('12) owner validUntil uzatma → DENY', async () => {
    await seedLink('o2', {
      linkTier: 'premium',
      validUntil: Timestamp.fromMillis(Date.now() + HOUR),
    });
    await assertFails(
      updateDoc(doc(userDb(), 'links', 'o2'), {
        validUntil: Timestamp.fromMillis(Date.now() + 10 * DAY),
      }),
    );
  });

  it('13) owner demoSubmissionUsed reset → DENY', async () => {
    await seedLink('o3', { linkTier: 'demo', demoSubmissionUsed: true, isActive: false });
    await assertFails(
      updateDoc(doc(userDb(), 'links', 'o3'), { demoSubmissionUsed: false }),
    );
  });

  it('14) owner deactivate (isActive true→false) → ALLOW', async () => {
    await seedLink('o4', {
      linkTier: 'premium',
      validUntil: Timestamp.fromMillis(Date.now() + HOUR),
    });
    await assertSucceeds(updateDoc(doc(userDb(), 'links', 'o4'), { isActive: false }));
  });
});
