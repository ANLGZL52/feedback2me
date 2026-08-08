/**
 * FeedbackToMe — Sunucu-yetkili IAP doğrulama + kredi verme.
 *
 * Neden: İstemci Firestore'a doğrudan `paidLinkCredits`/`isPremium` yazamaz
 * (firestore.rules kilitli). Kredi YALNIZCA burada, mağaza makbuzu doğrulandıktan
 * sonra Admin SDK ile verilir (Admin SDK güvenlik kurallarını bypass eder).
 *
 * Akış (istemci): satın alma tamamlanınca `iapVerify` çağrılır →
 *   { platform, productId, verificationData, transactionId } → sunucu doğrular →
 *   idempotent olarak +1 kredi yazar → istemci completePurchase yapar.
 *
 * Gerekli secret/param'lar (bkz. functions/README.md):
 *   - APPLE_SHARED_SECRET       (App Store Connect → App-Specific Shared Secret)
 *   - PLAY_SERVICE_ACCOUNT_JSON (Play Console erişimli service account JSON)
 *   - ANDROID_PACKAGE_NAME      (ör. com.feedbacktome.app)
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret, defineString } from 'firebase-functions/params';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { JWT } from 'google-auth-library';
import { createHash } from 'node:crypto';

initializeApp();
const db = getFirestore();

const APPLE_SHARED_SECRET = defineSecret('APPLE_SHARED_SECRET');
const PLAY_SERVICE_ACCOUNT_JSON = defineSecret('PLAY_SERVICE_ACCOUNT_JSON');
const ANDROID_PACKAGE_NAME = defineString('ANDROID_PACKAGE_NAME');

/** Ürün → verilecek kredi. Yalnızca bilinen ürünler kredi kazandırır. */
const CREDIT_BY_PRODUCT: Record<string, number> = {
  premium_link_single: 1,
};

const APPLE_PROD = 'https://buy.itunes.apple.com/verifyReceipt';
const APPLE_SANDBOX = 'https://sandbox.itunes.apple.com/verifyReceipt';

interface VerifyResult {
  ok: boolean;
  transactionId?: string;
  reason?: string;
}

/**
 * Apple makbuzunu doğrular (legacy verifyReceipt; StoreKit1 app-receipt).
 * Prod'da 21007 dönerse sandbox'a düşer.
 */
async function verifyApple(
  receiptData: string,
  productId: string,
  sharedSecret: string,
): Promise<VerifyResult> {
  const body = JSON.stringify({
    'receipt-data': receiptData,
    password: sharedSecret,
    'exclude-old-transactions': true,
  });
  async function call(url: string): Promise<any> {
    const res = await fetch(url, { method: 'POST', body });
    return (await res.json()) as any;
  }
  let json = await call(APPLE_PROD);
  if (json?.status === 21007) {
    json = await call(APPLE_SANDBOX);
  }
  if (json?.status !== 0) {
    return { ok: false, reason: `apple_status_${json?.status}` };
  }
  // Ürün eşleşen en yeni in_app kaydını bul.
  const inApp: any[] = json?.receipt?.in_app ?? json?.latest_receipt_info ?? [];
  const match = inApp
    .filter((t) => t?.product_id === productId)
    .sort((a, b) => Number(b?.purchase_date_ms ?? 0) - Number(a?.purchase_date_ms ?? 0))[0];
  if (!match) {
    return { ok: false, reason: 'apple_product_mismatch' };
  }
  return { ok: true, transactionId: String(match.transaction_id) };
}

/** Google Play satın alma token'ını androidpublisher API ile doğrular. */
async function verifyGoogle(
  productId: string,
  purchaseToken: string,
  serviceAccountJson: string,
  packageName: string,
): Promise<VerifyResult> {
  let creds: { client_email: string; private_key: string };
  try {
    creds = JSON.parse(serviceAccountJson);
  } catch {
    return { ok: false, reason: 'play_bad_service_account' };
  }
  const client = new JWT({
    email: creds.client_email,
    key: creds.private_key,
    scopes: ['https://www.googleapis.com/auth/androidpublisher'],
  });
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(packageName)}/purchases/products/` +
    `${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}`;
  const { token } = await client.getAccessToken();
  if (!token) return { ok: false, reason: 'play_no_access_token' };
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    return { ok: false, reason: `play_http_${res.status}` };
  }
  const data = (await res.json()) as any;
  // purchaseState: 0 = satın alındı, 1 = iptal, 2 = beklemede.
  if (data?.purchaseState !== 0) {
    return { ok: false, reason: `play_state_${data?.purchaseState}` };
  }
  return { ok: true, transactionId: String(data?.orderId ?? purchaseToken) };
}

export const iapVerify = onCall(
  {
    region: 'us-central1',
    secrets: [APPLE_SHARED_SECRET, PLAY_SERVICE_ACCOUNT_JSON],
    enforceAppCheck: false,
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Giriş gerekli.');
    }

    const data = (request.data ?? {}) as {
      platform?: string;
      productId?: string;
      verificationData?: string;
      transactionId?: string | null;
    };
    const platform = String(data.platform ?? '');
    const productId = String(data.productId ?? '');
    const verificationData = String(data.verificationData ?? '');
    if (!verificationData || !productId) {
      throw new HttpsError('invalid-argument', 'Eksik doğrulama verisi.');
    }
    const credit = CREDIT_BY_PRODUCT[productId];
    if (!credit) {
      throw new HttpsError('invalid-argument', 'Bilinmeyen ürün.');
    }

    // Mağaza doğrulaması.
    let result: VerifyResult;
    if (platform === 'ios' || platform === 'apple') {
      result = await verifyApple(verificationData, productId, APPLE_SHARED_SECRET.value());
    } else if (platform === 'android' || platform === 'google') {
      result = await verifyGoogle(
        productId,
        verificationData,
        PLAY_SERVICE_ACCOUNT_JSON.value(),
        ANDROID_PACKAGE_NAME.value(),
      );
    } else {
      throw new HttpsError('invalid-argument', 'Geçersiz platform.');
    }

    if (!result.ok) {
      throw new HttpsError('permission-denied', `Makbuz doğrulanamadı: ${result.reason}`);
    }

    // Idempotency anahtarı: mağaza işlem kimliği (yoksa doğrulama verisinin hash'i).
    const txId =
      result.transactionId ||
      data.transactionId ||
      createHash('sha256').update(verificationData).digest('hex');
    const key = `${platform}:${txId}`;
    const procRef = db.collection('processedPurchases').doc(key);
    const userRef = db.collection('users').doc(uid);

    // Tek transaction: replay kontrolü + kredi verme.
    const outcome = await db.runTransaction(async (tx) => {
      const proc = await tx.get(procRef);
      const user = await tx.get(userRef);
      if (proc.exists) {
        return { granted: false, alreadyProcessed: true, credits: user.get('paidLinkCredits') ?? 0 };
      }
      const cur = Number(user.get('paidLinkCredits') ?? 0);
      const next = cur + credit;
      tx.set(userRef, { paidLinkCredits: next }, { merge: true });
      tx.set(procRef, {
        uid,
        platform,
        productId,
        transactionId: txId,
        grantedCredits: credit,
        grantedAt: FieldValue.serverTimestamp(),
      });
      return { granted: true, alreadyProcessed: false, credits: next };
    });

    return { ok: true, ...outcome };
  },
);
