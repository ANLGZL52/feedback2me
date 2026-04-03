/// Railway REST API kullanımı: derleme sırasında dart-define ile verilir.
///
/// Örnek:
/// `flutter run --dart-define=USE_RAILWAY_API=true --dart-define=API_BASE_URL=https://xxx.up.railway.app --dart-define=DEV_AUTH_SECRET=...`
///
/// Sunucuda `ALLOW_DEV_AUTH=true` ve aynı `DEV_AUTH_SECRET` olmalı (geçici köprü).
/// İleride gerçek OAuth ile değiştirilecek.
class BackendConfig {
  BackendConfig._();

  static const bool useRailwayApi = bool.fromEnvironment(
    'USE_RAILWAY_API',
    defaultValue: false,
  );

  /// Sonunda `/` olmadan tam taban URL (ör. https://feedback2me-api.up.railway.app)
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// Sadece [useRailwayApi] iken; sunucudaki `DEV_AUTH_SECRET` ile aynı.
  static const String devAuthSecret = String.fromEnvironment(
    'DEV_AUTH_SECRET',
    defaultValue: '',
  );

  static bool get isRailwayBackendConfigured =>
      useRailwayApi && apiBaseUrl.isNotEmpty;
}
