/// App Store Connect ve Google Play Console'da aynı kimlikle ürün oluşturun.
///
/// **Apple (App Store Connect)**
/// 1. In-App Purchases: `premium_link_single` > tip **Consumable**.
/// 2. Screenshot ekleyip "Submit for Review" ile review'a sunun.
/// 3. Xcode > Runner target > Signing & Capabilities > **+ In-App Purchase**.
/// 4. Sandbox tester hesabı ile test edin (Settings > Developer > Sandbox Account).
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
