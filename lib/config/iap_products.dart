/// App Store Connect ve Google Play Console’da **aynı kimliklerle** ürün oluşturun.
///
/// **Apple (App Store Connect)**  
/// 1. Uygulama → Monetization → Subscriptions: grup aç, `premium_monthly` otomatik yenilenen abonelik.  
/// 2. In-App Purchases: `premium_link_single` → tip **Consumable**.  
/// 3. Xcode → Runner target → Signing & Capabilities → **+ In-App Purchase**.
///
/// **Google (Play Console)**  
/// 1. Monetize → Subscriptions: `premium_monthly` (+ temel plan / teklif).  
/// 2. Monetize → One-time products: **ürün kimliği** tam olarak `premium_link_single` (kod bu ID ile sorgular).  
///    Satın alma seçeneği kimliği (ör. `premium-link-single`) Play içindedir; Flutter `in_app_purchase` yine **ürün kimliği** ile çalışır.  
/// 3. `applicationId` (`android/app/build.gradle.kts`) ile Play’deki uygulama paketi aynı olmalı (`app.feedbacktome`).  
/// 4. Ayarlar → License testing ile test hesapları; test için imzalı AAB’yi iç/kapalı teste yükleyin.
///
/// Sandbox (iOS) ve iç test (Android) ile gerçek ödeme almadan doğrulayın.
class IapProducts {
  IapProducts._();

  /// Aylık premium abonelik — sınırsız premium link (24 saat) süresi boyunca.
  static const String premiumMonthly = 'premium_monthly';

  /// Tüketilebilir — hesaba +1 premium link kredisi (tek link, 24 saat).
  static const String premiumLinkSingle = 'premium_link_single';

  static Set<String> get all => {premiumMonthly, premiumLinkSingle};

  static bool isConsumable(String productId) =>
      productId == premiumLinkSingle;
}
