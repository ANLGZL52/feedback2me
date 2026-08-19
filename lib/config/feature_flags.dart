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
