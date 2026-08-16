// Firestore Security Rules — IAP ENTITLEMENT invariant tests (emulator).
// RUN (Java + Firestore emulator required):
//   cd test/rules && npm install
//   cd ../.. && firebase emulators:exec --only firestore "node --test test/rules"
//
// Scope: users doc entitlement lock (no client credit/premium escalation),
// processedPurchases isolation, and premium/demo link create that must atomically
// consume the correct entitlement. Duration/lifecycle rules are out of scope here.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { after, before, beforeEach, describe, it } from 'node:test';

import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, getDoc, writeBatch, increment } from 'firebase/firestore';

const PROJECT_ID = 'feedbacktome-rules-test';
const __dirname = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(__dirname, '..', '..', 'firestore.rules'), 'utf8');
const UID = 'owner1';

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules, host: '127.0.0.1', port: 8080 },
  });
});
after(async () => await testEnv.cleanup());
beforeEach(async () => await testEnv.clearFirestore());

const authed = () => testEnv.authenticatedContext(UID).firestore();
async function seedUser(data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', UID), { paidLinkCredits: 0, isPremium: false, freeDemoLinkUsed: false, ...data });
  });
}
const linkData = (tier) => ({ ownerId: UID, code: 'L1', linkTier: tier, isActive: true, demoSubmissionUsed: false, validUntil: new Date(Date.now() + 3600e3) });

describe('users doc — entitlement is server-authoritative', () => {
  it('create with credits==0 & isPremium==false -> ALLOWED', async () => {
    await assertSucceeds(setDoc(doc(authed(), 'users', UID), { paidLinkCredits: 0, isPremium: false, displayName: 'A' }));
  });
  it('create with paidLinkCredits>0 -> DENIED', async () => {
    await assertFails(setDoc(doc(authed(), 'users', UID), { paidLinkCredits: 5, isPremium: false }));
  });
  it('create with isPremium:true -> DENIED', async () => {
    await assertFails(setDoc(doc(authed(), 'users', UID), { paidLinkCredits: 0, isPremium: true }));
  });
  it('client INCREMENT paidLinkCredits -> DENIED', async () => {
    await seedUser({ paidLinkCredits: 1 });
    await assertFails(updateDoc(doc(authed(), 'users', UID), { paidLinkCredits: increment(1) }));
  });
  it('client sets paidLinkCredits to a larger absolute value -> DENIED', async () => {
    await seedUser({ paidLinkCredits: 1 });
    await assertFails(updateDoc(doc(authed(), 'users', UID), { paidLinkCredits: 99 }));
  });
  it('client DECREMENT paidLinkCredits (consume) -> ALLOWED', async () => {
    await seedUser({ paidLinkCredits: 2 });
    await assertSucceeds(updateDoc(doc(authed(), 'users', UID), { paidLinkCredits: increment(-1) }));
  });
  it('client sets isPremium:true -> DENIED', async () => {
    await seedUser({ paidLinkCredits: 0 });
    await assertFails(updateDoc(doc(authed(), 'users', UID), { isPremium: true }));
  });
  it('client extends premiumUntil -> DENIED', async () => {
    await seedUser({ paidLinkCredits: 0, premiumUntil: null });
    await assertFails(updateDoc(doc(authed(), 'users', UID), { premiumUntil: new Date(Date.now() + 1e9) }));
  });
  it('client resets freeDemoLinkUsed true->false -> DENIED', async () => {
    await seedUser({ freeDemoLinkUsed: true });
    await assertFails(updateDoc(doc(authed(), 'users', UID), { freeDemoLinkUsed: false }));
  });
  it('legitimate profile field update (displayName) -> ALLOWED', async () => {
    await seedUser({ paidLinkCredits: 1 });
    await assertSucceeds(updateDoc(doc(authed(), 'users', UID), { displayName: 'New Name' }));
  });
});

describe('processedPurchases — client has no access', () => {
  it('client read -> DENIED', async () => {
    await assertFails(getDoc(doc(authed(), 'processedPurchases', 'ios:tx1')));
  });
  it('client write -> DENIED', async () => {
    await assertFails(setDoc(doc(authed(), 'processedPurchases', 'ios:tx1'), { grantedCredits: 1 }));
  });
});

describe('link create — atomic entitlement consumption', () => {
  it('PREMIUM create with credit before>=1 and after==before-1 (same batch) -> ALLOWED', async () => {
    await seedUser({ paidLinkCredits: 1 });
    const db = authed();
    const b = writeBatch(db);
    b.set(doc(db, 'links', 'L1'), linkData('premium'));
    b.update(doc(db, 'users', UID), { paidLinkCredits: increment(-1) });
    await assertSucceeds(b.commit());
  });
  it('PREMIUM create WITHOUT decrementing a credit -> DENIED', async () => {
    await seedUser({ paidLinkCredits: 1 });
    const db = authed();
    await assertFails(setDoc(doc(db, 'links', 'L1'), linkData('premium')));
  });
  it('PREMIUM create with ZERO credits -> DENIED', async () => {
    await seedUser({ paidLinkCredits: 0 });
    const db = authed();
    const b = writeBatch(db);
    b.set(doc(db, 'links', 'L1'), linkData('premium'));
    b.update(doc(db, 'users', UID), { paidLinkCredits: increment(-1) });
    await assertFails(b.commit());
  });
  it('DEMO first create (freeDemoLinkUsed false->true, same batch) -> ALLOWED', async () => {
    await seedUser({ freeDemoLinkUsed: false });
    const db = authed();
    const b = writeBatch(db);
    b.set(doc(db, 'links', 'L1'), linkData('demo'));
    b.set(doc(db, 'users', UID), { freeDemoLinkUsed: true }, { merge: true });
    await assertSucceeds(b.commit());
  });
  it('DEMO second create (already used) -> DENIED', async () => {
    await seedUser({ freeDemoLinkUsed: true });
    const db = authed();
    const b = writeBatch(db);
    b.set(doc(db, 'links', 'L1'), linkData('demo'));
    b.set(doc(db, 'users', UID), { freeDemoLinkUsed: true }, { merge: true });
    await assertFails(b.commit());
  });
});
