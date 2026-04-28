/// App Store Connect ve Google Play Console'da aynı kimlikle ürün oluşturun.
///
/// ---------------------------------------------------------------------------
/// APPLE — Guideline 2.1(b): Ürün tek başına yetmez; uygulama sürümüyle birlikte
/// INCELEMEYE EKLENMELİ. Aksi halde reddedilir.
///
/// 1) My Apps → Uygulama → **Features** (veya **Monetization**) → **In-App Purchases**
///    → Consumable oluştur: Product ID **premium_link_single** (kodla birebir aynı).
/// 2) Ürün sayfasında: en az bir dil için Display Name + Description, fiyat,
///    **Review Information** altında **screenshot** (Apple'ın istediği iPhone boyutu).
/// 3) Ürün durumu **Ready to Submit** olmalı.
/// 4) **Yeni bir uygulama sürümü** (Prepare for Submission) aç → Build seç →
///    sayfada **In-App Purchases** bölümünden
///    bu IAP'yi **bu sürüme ekleyin** → **Add to App Review** / review paketine dahil edin.
/// 5) Sonra **Submit for Review**. Sadece binary gönderip IAP'yi bağlamak RED sebebidir.
///
/// Xcode: Runner → Signing & Capabilities → **In-App Purchase** yeteneği açık olsun.
///
/// **Google (Play Console)**
/// 1. Monetize > One-time products: `premium_link_single` (Consumable).
/// 2. `applicationId` (`android/app/build.gradle.kts`) ile Play'deki uygulama paketi aynı olmalı.
/// 3. License testing ile test hesapları; imzalı AAB'yi iç/kapalı teste yükleyin.
class IapProducts {
  IapProducts._();

  /// Tüketilebilir (consumable) — hesaba +1 premium link kredisi (tek link, 24 saat).
  static const String premiumLinkSingle = 'premium_link_single';

  static Set<String> get all => {premiumLinkSingle};

  static bool isConsumable(String productId) =>
      productId == premiumLinkSingle;
}
