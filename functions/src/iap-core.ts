/**
 * IAP core — provider-independent, testable credit logic.
 * Separated from the Apple/Google network calls so the security-critical parts
 * (product allow-list, server-determined amount, store-authoritative identity,
 * idempotent atomic grant) can be unit/emulator tested without hitting the stores.
 */
import { createHash } from 'node:crypto';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';

/**
 * Product -> credit. ONLY allow-listed products grant credit.
 * `premium_link_single_v2` = the NEW client's purchase product.
 * `premium_link_single`    = LEGACY, kept for RECOVERY of already-completed store
 *   transactions from old clients (after the product is removed from sale, no NEW
 *   legacy purchase is possible; store-authoritative idempotency ensures each real
 *   transaction grants +1 exactly once, so accepting it for recovery is safe).
 */
export const CREDIT_BY_PRODUCT: Record<string, number> = {
  premium_link_single_v2: 1,
  premium_link_single: 1,
};

/** Server-determined credit for a product; null = unknown product (grants nothing). */
export function creditForProduct(productId: string): number | null {
  return CREDIT_BY_PRODUCT[productId] ?? null;
}

/**
 * Route a purchase platform to a verification action. `androidEnabled=false`
 * (the iOS-only milestone: Google Play verification not configured) FAILS CLOSED:
 * an Android request routes to `android_disabled`, which the handler rejects with
 * a failed-precondition — it never reaches grantCredit, so it grants 0 credits and
 * writes no processedPurchases document.
 */
export type PlatformRoute = 'apple' | 'android' | 'android_disabled' | 'invalid';
export function routePlatform(platform: string, androidEnabled: boolean): PlatformRoute {
  if (platform === 'ios' || platform === 'apple') return 'apple';
  if (platform === 'android' || platform === 'google') return androidEnabled ? 'android' : 'android_disabled';
  return 'invalid';
}

/**
 * Result of a store receipt verification. `transactionId` (when ok) is the
 * STORE-AUTHORITATIVE unique purchase identity. `transient` distinguishes a
 * retryable failure (network / store outage / server config) from a permanent
 * rejection (invalid / wrong-product / cancelled) — see index.ts error mapping.
 */
export interface VerifyResult {
  ok: boolean;
  transactionId?: string;
  reason?: string;
  transient?: boolean;
}

/**
 * Apple statuses that are RETRYABLE (do not permanently reject the purchase):
 *   21004 shared-secret mismatch  -> our server-side secret config (fix + retry)
 *   21005 receipt server unavailable
 *   21009 internal data access error
 *   21100-21199 internal errors
 * Everything else (21000/21002/21003/21008/21010/...) is a permanent reject.
 */
function appleStatusTransient(status: number): boolean {
  return (
    status === 21004 ||
    status === 21005 ||
    status === 21009 ||
    (status >= 21100 && status <= 21199)
  );
}

/**
 * Parse an Apple verifyReceipt JSON into a VerifyResult (PURE — no network).
 * - status must be 0 (success); otherwise reject (transient-classified).
 * - the requested productId MUST appear in the receipt (product binding).
 * - the newest matching in_app transaction is chosen.
 * - transactionId is taken from the STORE response; if absent the receipt is
 *   rejected (never coerced to a client-supplied value).
 */
export function parseAppleReceipt(json: any, productId: string): VerifyResult {
  const status = json && typeof json.status === 'number' ? json.status : -1;
  if (status !== 0) {
    return { ok: false, reason: `apple_status_${status}`, transient: appleStatusTransient(status) };
  }
  const inApp: any[] = (json.receipt && json.receipt.in_app) || json.latest_receipt_info || [];
  const match = inApp
    .filter((t) => t && t.product_id === productId)
    .sort((a, b) => Number((b && b.purchase_date_ms) || 0) - Number((a && a.purchase_date_ms) || 0))[0];
  if (!match) {
    return { ok: false, reason: 'apple_product_mismatch', transient: false };
  }
  const txId = match.transaction_id != null ? String(match.transaction_id) : '';
  if (!txId) {
    return { ok: false, reason: 'apple_no_transaction_id', transient: false };
  }
  return { ok: true, transactionId: txId };
}

/**
 * Parse a Google androidpublisher ProductPurchase into a VerifyResult (PURE).
 * The productId/packageName binding is enforced by the request URL (caller);
 * here we require a purchased state and derive the STORE identity.
 * - purchaseState 0 = purchased; 2 = pending (transient, no credit yet);
 *   anything else (1 = cancelled) = permanent reject.
 * - identity: orderId when present, else the store-verified purchaseToken
 *   (still store material, never a client-supplied value).
 */
export function parseGooglePurchase(data: any, purchaseToken: string): VerifyResult {
  if (!data || typeof data !== 'object') {
    return { ok: false, reason: 'play_empty', transient: true };
  }
  const state = data.purchaseState;
  if (state === 2) {
    return { ok: false, reason: 'play_state_pending', transient: true };
  }
  if (state !== 0) {
    return { ok: false, reason: `play_state_${state}`, transient: false };
  }
  const id = data.orderId != null ? String(data.orderId) : purchaseToken ? String(purchaseToken) : '';
  if (!id) {
    return { ok: false, reason: 'play_no_identity', transient: false };
  }
  return { ok: true, transactionId: id };
}

/**
 * Idempotency key — STORE-AUTHORITATIVE ONLY.
 * Uses the store-verified transaction id. When the store did not surface a
 * separate id, falls back to a deterministic hash of the store-verified
 * material (receipt / purchaseToken). It NEVER incorporates any client-supplied
 * value, so a caller replaying the same verified purchase with a different
 * client transactionId cannot mint a second grant.
 */
export function idempotencyKey(
  platform: string,
  storeTxId: string | undefined | null,
  verificationData: string,
): string {
  const store = storeTxId != null ? String(storeTxId).trim() : '';
  const txId =
    store !== ''
      ? store
      : 'sha256:' + createHash('sha256').update(String(verificationData || '')).digest('hex');
  return `${platform}:${txId}`;
}

export interface GrantResult {
  granted: boolean;
  alreadyProcessed: boolean;
  credits: number;
}

/**
 * Idempotent, atomic credit grant via Admin SDK (bypasses Firestore rules).
 * The credit amount is SERVER-determined (caller passes creditForProduct()).
 * A processedPurchases doc keyed by the STORE transaction makes replay and
 * concurrent verifies safe: a second grant with the same key finds the doc and
 * grants nothing. Firestore transaction retries serialize concurrent grants.
 * clientTransactionId is stored as debug/correlation metadata ONLY — it is not
 * part of the key and has no security effect.
 */
export async function grantCredit(
  db: Firestore,
  params: {
    uid: string;
    key: string;
    platform: string;
    productId: string;
    credit: number;
    clientTransactionId?: string | null;
  },
): Promise<GrantResult> {
  const procRef = db.collection('processedPurchases').doc(params.key);
  const userRef = db.collection('users').doc(params.uid);
  return db.runTransaction(async (tx) => {
    const proc = await tx.get(procRef);
    const user = await tx.get(userRef);
    if (proc.exists) {
      return { granted: false, alreadyProcessed: true, credits: Number(user.get('paidLinkCredits') ?? 0) };
    }
    const cur = Number(user.get('paidLinkCredits') ?? 0);
    const next = cur + params.credit;
    tx.set(userRef, { paidLinkCredits: next }, { merge: true });
    tx.set(procRef, {
      uid: params.uid,
      platform: params.platform,
      productId: params.productId,
      transactionId: params.key.split(':').slice(1).join(':'),
      clientTransactionId: params.clientTransactionId ?? null,
      grantedCredits: params.credit,
      grantedAt: FieldValue.serverTimestamp(),
    });
    return { granted: true, alreadyProcessed: false, credits: next };
  });
}
