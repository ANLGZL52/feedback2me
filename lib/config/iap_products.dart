/// IAP ürün kimlikleri. SALT-KREDİ modeli: her başarılı doğrulanmış satın alma
/// hesaba +1 premium link kredisi yazar (sunucu-yetkili iapVerify).
///
/// ---------------------------------------------------------------------------
/// ÜRÜN-KİMLİĞİ GÖÇÜ (canlı eski istemciler için güvenli):
///   - `premium_link_single`      → ESKİ (yayınlanmış) istemcilerin ürünü. YENİ
///     istemci bununla YENİ satın alma BAŞLATMAZ. Yalnızca eski istemcilerde
///     kalmış/bekleyen doğrulanmış işlemler güncelleme sonrası SUNUCUDA kurtarılır.
///   - `premium_link_single_v2`   → YENİ (sunucu-yetkili) istemcinin satın aldığı
///     ürün. Kredi yalnızca iapVerify ile verilir; istemci paidLinkCredits yazmaz.
///
/// Neden ayrı ürün: eski `premium_link_single` App Store'da SATIŞTAN KALDIRILIR →
/// zaten kurulu eski binary'ler artık YENİ eski-ürün satın alması yapamaz (mağaza
/// reddeder). Bu, "mağaza öder ama kredi gelmez" sorununu (kilitli kurallar +
/// client-side grant eski istemci) MAĞAZA SEVİYESİNDE engeller — istemci-taraflı
/// bir min-sürüm kapısına güvenmeden (eski binary o kapıyı içermez).
///
/// APPLE: Consumable, uygulama sürümüyle birlikte incelemeye eklenmeli (2.1b).
/// GOOGLE: Monetize > One-time products (Consumable), applicationId ile eşleşmeli.
class IapProducts {
  IapProducts._();

  /// ESKİ ürün — yalnızca kurtarma/doğrulama için (yeni satın alma İÇİN DEĞİL).
  static const String premiumLinkSingle = 'premium_link_single';

  /// YENİ ürün — yeni istemcinin satın aldığı tek ürün.
  static const String premiumLinkSingleV2 = 'premium_link_single_v2';

  /// Yeni istemcinin sorgulayıp SATIN ALDIĞI ürün(ler) — yalnızca v2.
  static Set<String> get purchasable => {premiumLinkSingleV2};

  /// Teslimat/kurtarmada kabul edilen ürünler: v2 (yeni) + eski (kurtarma).
  /// iapVerify allow-list'i ile aynı olmalı (functions/src/iap-core.ts).
  static Set<String> get recoverable => {premiumLinkSingle, premiumLinkSingleV2};

  /// Bu ürün kredi verebilecek bilinen bir ürün mü (teslimat/kurtarma).
  static bool isKnownCreditProduct(String productId) =>
      recoverable.contains(productId);

  /// Geriye dönük uyum: sorgulanacak ürünler = satın alınabilir olanlar.
  static Set<String> get all => purchasable;
}
