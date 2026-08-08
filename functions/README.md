# FeedbackToMe — Cloud Functions (IAP güvenliği)

Sunucu-yetkili IAP makbuz doğrulama + kredi verme. Kredi/premium alanları
istemciden yazılamaz (`firestore.rules` kilitli); yalnızca `iapVerify`
fonksiyonu Admin SDK ile yazar (kuralları bypass eder).

## Ne çözüyor (P0.2)
- **Bedava-premium açığı:** İstemci artık `paidLinkCredits`/`isPremium`'u
  yükseltemez. Kredi yalnızca **doğrulanmış mağaza makbuzu** ile verilir.
- **Replay koruması:** Her işlem `processedPurchases/{platform:txId}` ile
  tekilleştirilir; aynı makbuz iki kez kredi vermez (app yeniden açılsa bile).

## ⚠️ Koordineli sürüm (birlikte deploy edilmeli)
`firestore.rules` + bu fonksiyon + yeni app derlemesi **birlikte** yayınlanmalı.
Kuralları tek başına deploy edersen, fonksiyon yokken **gerçek satın almalar
kredi veremez**. Sıra:
1. Fonksiyonu deploy et (aşağıdaki adımlar).
2. `firebase deploy --only firestore:rules`
3. Yeni app derlemesini (cloud_functions'lı) mağazaya gönder.

## Gereksinimler
- **Firebase Blaze planı** (fonksiyonun Apple/Google'a dışa HTTPS çağrısı için).
- Node 20 (fonksiyon runtime'ı; yerel derleme için Node 18+ yeterli).

## Kurulum
```bash
cd functions
npm install
npm run build        # tsc → lib/
```

## Secret'lar / parametreler
Fonksiyon üç değer bekler:

| Ad | Tür | Nereden |
|----|-----|---------|
| `APPLE_SHARED_SECRET` | secret | App Store Connect → App → App-Specific Shared Secret |
| `PLAY_SERVICE_ACCOUNT_JSON` | secret | Play Console erişimli service account JSON (tek satır) |
| `ANDROID_PACKAGE_NAME` | param | ör. `com.feedbacktome.app` |

Secret ayarla:
```bash
firebase functions:secrets:set APPLE_SHARED_SECRET
firebase functions:secrets:set PLAY_SERVICE_ACCOUNT_JSON   # dosya içeriğini yapıştır
```
`ANDROID_PACKAGE_NAME` için deploy sırasında sorulur ya da `.env` /
`firebase.json` param olarak verilir.

**Google Play service account:** Google Cloud Console'da SA oluştur → Play
Console → Users & permissions → bu SA'ya "View financial data / Manage orders"
izni ver → JSON anahtarı indir.

## Deploy
```bash
firebase deploy --only functions
```

## Test (emülatör)
```bash
npm run serve   # firebase emulators:start --only functions
```
Emülatörde `firestore.rules` kredi kısıtları da denenebilir; gerçek mağaza
doğrulaması için sandbox makbuzları gerekir.

## Notlar / kısıtlar
- **Apple:** legacy `verifyReceipt` (StoreKit1 app-receipt) kullanılır; prod'da
  `21007` dönerse otomatik sandbox'a düşer. Uygulama StoreKit2/JWS'e geçerse
  App Store Server API yoluna güncellenmeli.
- **Google:** consumable, istemcide `autoConsume: true` ile tüketiliyor; sunucu
  yalnızca token'ı doğrular (purchaseState==0) ve `orderId`'yi idempotency
  anahtarı yapar.
- Fonksiyon `us-central1`'de; istemci `FirebaseFunctions.instance` varsayılanı
  da aynı bölge.
