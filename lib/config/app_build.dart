/// Uygulama build numarası — pubspec `version: x.y.z+BUILD` ile SENKRON TUTULMALI.
///
/// Min-version gate (Phase 3/4 old-client cutover) bu sabiti Firestore
/// `appConfig/version.minSupportedBuild` ile karşılaştırır: `kAppBuild` altındaki
/// eski owner client'lar link oluşturmadan önce "güncelleme gerekli" ekranı görür.
/// package_info_plus GEREKMEZ → platform-bağımsız (Android/iOS/web aynı sabit).
///
/// SÜRÜM YÜKSELTİRKEN: pubspec.yaml `version:` build numarasını değiştirdiğinde
/// burayı da güncelle.
const int kAppBuild = 20;
