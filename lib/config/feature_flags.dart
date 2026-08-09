// FeedbackToMe 2.0 — Özellik bayrakları (kademeli geçiş / geri alınabilirlik).
//
// Migration stratejisi: yeni topluluk özeti eski basit özetin YANINDA gelir;
// bayrakla açılır/kapanır. Eski kod, doğrulama tamamlanana kadar silinmez.

/// true: yeni Topluluk Özeti (Crowd Score + reaction + AI'nın yalnızca
/// yorumları özetlediği görünüm). false: eski basit istek özeti.
const bool kUseCommunitySummary = bool.fromEnvironment(
  'USE_COMMUNITY_SUMMARY',
  defaultValue: true,
);

/// true: eski "Detaylı rapor" (AI danışman/koç raporu) girişini göster.
/// Yeni ürün vizyonu (AI kendi teknik değerlendirmesini üretmez) gereği
/// varsayılan KAPALI. Kod migration tamamlanınca fiziksel olarak silinecek.
const bool kShowDetailedReport = bool.fromEnvironment(
  'SHOW_DETAILED_REPORT',
  defaultValue: false,
);

/// TEST MODU — iç test kolaylığı. Açıkken oluşturulan link:
///   • uzun ömürlü (24 saat / 10 dk süre sınırı KALKAR — bkz. [kTestLinkValidDays]),
///   • premium (çok yorum kabul eder, demo tek-yorum sınırı yok),
///   • ücretsiz (kredi/demo tüketmez).
///
/// ⚠️ ÜRETİMDE KAPALI OLMALI: açıkken kredi kapısı bypass edilir (P0.2 güvenlik
/// kilidiyle çelişir). Yalnızca iç test derlemesinde aç:
///   flutter build ... --dart-define=TEST_MODE=true
/// Genel yayına çıkmadan önce bayrağı verme (varsayılan `false`).
const bool kTestMode = bool.fromEnvironment(
  'TEST_MODE',
  defaultValue: false,
);

/// TEST MODU link ömrü (gün). Süre sonu akışını manuel tetikleyecek asıl test
/// sistemini sonra kuracağız; şimdilik pratikte "süre sınırı yok" demek için uzun.
const int kTestLinkValidDays = int.fromEnvironment(
  'TEST_LINK_DAYS',
  defaultValue: 3650,
);
