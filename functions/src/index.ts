/**
 * FeedbackToMe — aiSummary: the trusted SERVER-SIDE OpenAI gateway.
 *
 * Why: the OpenAI key must NOT live in the Flutter client. This 2nd-gen HTTPS
 * callable holds OPENAI_API_KEY server-side (Secret Manager), verifies the
 * Firebase Auth context the client already has, enforces payload limits + a
 * per-user rate limit, and calls OpenAI with a SERVER-CHOSEN model/prompt. The
 * client sends only feedback-derived content and receives a normalized result.
 *
 * It is deliberately NOT a generic chat proxy: the client cannot submit a model,
 * a system prompt, messages, temperature, an API key, or a provider URL. The full
 * (network-free, unit-tested) pipeline lives in ai-core.ts:handleAiSummary — this
 * file only supplies real dependencies and maps AiError -> HttpsError.
 *
 * Secret (bind ONLY to this function; configure before deploy — see README):
 *   firebase functions:secrets:set OPENAI_API_KEY
 *
 * NOTE: App Check is NOT enforced yet (enforceAppCheck:false) because the Flutter
 * client does not send App Check tokens today. Firebase Auth is still required.
 * See README "App Check activation" for the safe enable path.
 */
import { onCall, HttpsError, type CallableRequest } from 'firebase-functions/v2/https';
import { defineSecret, defineString } from 'firebase-functions/params';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { randomUUID } from 'node:crypto';
import { JWT } from 'google-auth-library';
import {
  handleAiSummary,
  evaluateRateLimit,
  AiError,
  DEFAULT_RATE_LIMIT,
  type HandlerLogEvent,
  type RateWindowState,
} from './ai-core.js';
import {
  creditForProduct,
  idempotencyKey,
  grantCredit,
  parseAppleReceipt,
  parseGooglePurchase,
  routePlatform,
  type VerifyResult,
} from './iap-core.js';

// Guarded so both callables (aiSummary, iapVerify) can initialize the Admin app
// exactly once even though each is defined in this single file.
if (!getApps().length) initializeApp();

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
// IAP verification. iOS milestone: iapVerify binds ONLY APPLE_SHARED_SECRET.
// Google Play verification is NOT configured yet — PLAY_SERVICE_ACCOUNT_JSON is
// intentionally NOT declared/bound so the Android path fails closed (see below).
// ANDROID_PACKAGE_NAME stays (non-secret) for the future Android milestone.
const APPLE_SHARED_SECRET = defineSecret('APPLE_SHARED_SECRET');
const ANDROID_PACKAGE_NAME = defineString('ANDROID_PACKAGE_NAME');

/**
 * Per-user fixed-window rate limit via an atomic Firestore transaction on
 * `aiUsage/{uid}`. Admin SDK writes bypass security rules, and the collection is
 * default-denied to clients (no rule grants access) — so NO firestore.rules
 * change is required.
 */
async function consumeRateLimit(
  db: Firestore,
  uid: string,
  now: number,
): Promise<{ allowed: boolean; retryAfterMs: number; remaining: number }> {
  const ref = db.collection('aiUsage').doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const state = (snap.exists ? (snap.data() as RateWindowState) : null) ?? null;
    const decision = evaluateRateLimit(state, now, DEFAULT_RATE_LIMIT);
    if (decision.allowed) {
      tx.set(ref, { windowStart: decision.nextState.windowStart, count: decision.nextState.count });
    }
    return {
      allowed: decision.allowed,
      retryAfterMs: decision.retryAfterMs,
      remaining: decision.remaining,
    };
  });
}

function emit(e: HandlerLogEvent): void {
  const line = JSON.stringify(e.event);
  if (e.level === 'error') console.error(line);
  else if (e.level === 'warn') console.warn(line);
  else console.log(line);
}

export const aiSummary = onCall(
  {
    region: 'us-central1',
    secrets: [OPENAI_API_KEY],
    enforceAppCheck: false, // client not App Check-ready yet; Firebase Auth still required
    timeoutSeconds: 240, // must exceed the 180s provider budget (ai-core REQUEST_TIMEOUT_MS)
    memory: '256MiB',
    // Cost guard: cap fan-out so a traffic burst cannot multiply OpenAI spend
    // without bound. Generous for legitimate per-user report generation.
    maxInstances: 10,
  },
  async (request: CallableRequest) => {
    try {
      return await handleAiSummary(request.auth?.uid ?? null, request.data, {
        apiKey: OPENAI_API_KEY.value(),
        consumeRateLimit: (uid, now) => consumeRateLimit(getFirestore(), uid, now),
        newRequestId: randomUUID,
        log: emit,
      });
    } catch (e) {
      if (e instanceof AiError) {
        throw new HttpsError(e.httpsCode, e.message, e.details);
      }
      // Unexpected: never leak internals.
      console.error(JSON.stringify({ source: 'functions', service: 'aiSummary', eventType: 'server.runtime.error', severity: 'ERROR', message: 'aiSummary unexpected error' }));
      throw new HttpsError('internal', 'Beklenmeyen hata.', { errorCode: 'AI_UNEXPECTED' });
    }
  },
);

// ===========================================================================
// iapVerify — server-authoritative IAP receipt verification + credit grant.
//
// The client can no longer write paidLinkCredits (firestore.rules is locked);
// credit is granted ONLY here, after a store receipt is verified, via the Admin
// SDK (which bypasses rules). Flow: purchase -> iapVerify({platform, productId,
// verificationData, transactionId}) -> verify with Apple/Google -> idempotent
// +1 credit. The idempotency key is store-authoritative (never client-supplied),
// so replays grant +0. Provider parsing/replay/atomic-grant logic is in
// iap-core.ts (network-free, unit-tested).
//
// iOS milestone: binds ONLY APPLE_SHARED_SECRET (secret). Google Play verification
// is NOT configured — the Android path fails closed (ANDROID_VERIFICATION_NOT_
// CONFIGURED). The Android milestone re-adds PLAY_SERVICE_ACCOUNT_JSON (secret) +
// ANDROID_PACKAGE_NAME (param) and sets ANDROID_VERIFY_ENABLED=true.
// ===========================================================================

const APPLE_PROD = 'https://buy.itunes.apple.com/verifyReceipt';
const APPLE_SANDBOX = 'https://sandbox.itunes.apple.com/verifyReceipt';

/** Verify an Apple receipt (legacy verifyReceipt; 21007 -> retry sandbox). Network/parse error = transient. */
async function verifyApple(receiptData: string, productId: string, sharedSecret: string): Promise<VerifyResult> {
  const body = JSON.stringify({ 'receipt-data': receiptData, password: sharedSecret, 'exclude-old-transactions': true });
  async function call(url: string): Promise<any> {
    const res = await fetch(url, { method: 'POST', body });
    return (await res.json()) as any;
  }
  let json: any;
  try {
    json = await call(APPLE_PROD);
    if (json?.status === 21007) json = await call(APPLE_SANDBOX);
  } catch {
    return { ok: false, reason: 'apple_network', transient: true };
  }
  return parseAppleReceipt(json, productId);
}

/** Verify a Google Play purchase token via androidpublisher. Product/package bound by the URL path. */
async function verifyGoogle(productId: string, purchaseToken: string, serviceAccountJson: string, packageName: string): Promise<VerifyResult> {
  let creds: { client_email: string; private_key: string };
  try {
    creds = JSON.parse(serviceAccountJson);
  } catch {
    return { ok: false, reason: 'play_bad_service_account', transient: true };
  }
  const client = new JWT({ email: creds.client_email, key: creds.private_key, scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(packageName)}/purchases/products/` +
    `${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}`;
  let res: Response;
  try {
    const { token } = await client.getAccessToken();
    if (!token) return { ok: false, reason: 'play_no_access_token', transient: true };
    res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  } catch {
    return { ok: false, reason: 'play_network', transient: true };
  }
  if (!res.ok) return { ok: false, reason: `play_http_${res.status}`, transient: res.status >= 500 };
  let data: any;
  try {
    data = (await res.json()) as any;
  } catch {
    return { ok: false, reason: 'play_bad_json', transient: false };
  }
  return parseGooglePurchase(data, purchaseToken);
}

export const iapVerify = onCall(
  {
    region: 'us-central1',
    secrets: [APPLE_SHARED_SECRET], // iOS milestone: Apple only (Android fails closed)
    enforceAppCheck: false, // client not App Check-ready yet; Firebase Auth still required
  },
  async (request: CallableRequest) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Giriş gerekli.');

    const data = (request.data ?? {}) as {
      platform?: string;
      productId?: string;
      verificationData?: string;
      transactionId?: string | null;
    };
    const platform = String(data.platform ?? '');
    const productId = String(data.productId ?? '');
    const verificationData = String(data.verificationData ?? '');
    if (!verificationData || !productId) throw new HttpsError('invalid-argument', 'Eksik doğrulama verisi.');
    const credit = creditForProduct(productId);
    if (credit == null) throw new HttpsError('invalid-argument', 'Bilinmeyen ürün.');

    // iOS milestone: Google Play verification is NOT configured -> Android FAILS
    // CLOSED here (before grantCredit), so it grants 0 credits and writes no
    // processedPurchases. Re-enable with the Android milestone (androidEnabled=true
    // + PLAY_SERVICE_ACCOUNT_JSON secret + verifyGoogle wired below).
    const ANDROID_VERIFY_ENABLED = false;
    let result: VerifyResult;
    const route = routePlatform(platform, ANDROID_VERIFY_ENABLED);
    if (route === 'apple') {
      result = await verifyApple(verificationData, productId, APPLE_SHARED_SECRET.value());
    } else if (route === 'android_disabled') {
      throw new HttpsError('failed-precondition', 'Android doğrulama yapılandırılmadı.', {
        errorCode: 'ANDROID_VERIFICATION_NOT_CONFIGURED',
      });
    } else {
      // 'invalid' (and, until the Android milestone, unreachable 'android').
      throw new HttpsError('invalid-argument', 'Geçersiz platform.');
    }

    if (!result.ok) {
      // Transient (network/store outage/config) -> 'unavailable': client keeps the
      // purchase queued and retries (no loss). Permanent reject -> 'permission-denied':
      // client consumes it, no credit.
      if (result.transient) throw new HttpsError('unavailable', `Doğrulama geçici olarak başarısız (retry): ${result.reason}`);
      throw new HttpsError('permission-denied', `Makbuz doğrulanamadı: ${result.reason}`);
    }

    // Idempotent, atomic grant. Key derives ONLY from store-authoritative identity
    // (result.transactionId or a hash of the verified material) — the client
    // transactionId is correlation metadata only, never part of the key.
    const key = idempotencyKey(platform, result.transactionId, verificationData);
    const outcome = await grantCredit(getFirestore(), {
      uid,
      key,
      platform,
      productId,
      credit,
      clientTransactionId: data.transactionId ?? null,
    });
    return { ok: true, ...outcome };
  },
);
