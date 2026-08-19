import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/app_build.dart';

/// Owner app min-version gate (old-client cutover, Phase 3/4).
///
/// Firestore `appConfig/version` dokümanını okur:
///   { minSupportedBuild: int, latestBuild: int }
/// `kAppBuild < minSupportedBuild` ise güncelleme zorunludur.
///
/// FAIL-OPEN: doküman yok / alan yok / offline / hata / timeout → `false`
/// (uygulamayı ağ hatasında KİLİTLEME). Public feedback akışı (`/f/<code>`) bu
/// gate'ten GEÇMEZ — yalnız owner app'e uygulanır. Fingerprint/tracking YOK.
class VersionGate {
  const VersionGate._();

  static const String docPath = 'appConfig/version';

  /// Saf, test edilebilir karar. minSupportedBuild null → güncelleme gerekmez.
  static bool updateRequiredFor(int appBuild, int? minSupportedBuild) {
    if (minSupportedBuild == null) return false;
    return appBuild < minSupportedBuild;
  }

  /// Firestore'dan okuyup [updateRequiredFor] uygular. Herhangi bir hata → false.
  static Future<bool> isUpdateRequired() async {
    try {
      final snap = await FirebaseFirestore.instance
          .doc(docPath)
          .get()
          .timeout(const Duration(seconds: 2));
      final min = (snap.data()?['minSupportedBuild'] as num?)?.toInt();
      return updateRequiredFor(kAppBuild, min);
    } catch (_) {
      return false; // FAIL-OPEN
    }
  }

  /// Güncelleme için platforma uygun mağaza URL'si.
  static Uri storeUrl() {
    if (kIsWeb) {
      return Uri.parse('https://feedbacktome-79655.web.app/');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return Uri.parse('https://apps.apple.com/app/id6762295382');
      case TargetPlatform.android:
        return Uri.parse(
            'https://play.google.com/store/apps/details?id=app.feedbacktome');
      default:
        return Uri.parse('https://feedbacktome-79655.web.app/');
    }
  }
}
