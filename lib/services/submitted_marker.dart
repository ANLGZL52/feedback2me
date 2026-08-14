import 'package:shared_preferences/shared_preferences.dart';

/// Same-browser / same-device anti-repeat marker.
///
/// UX CAYDIRICI — GÜVENLİK DEĞİL. Marker YALNIZ başarılı submit sonrası yazılır.
/// Storage temizleme, gizli sekme, başka tarayıcı/cihaz ile AŞILABİLİR; bu
/// yüzden "bir kişi yalnız bir kez yanıt verir" gibi mutlak iddia YOK.
/// Demo tek-yorum / süre garantileri buna BAĞLI DEĞİL — kaynak-doğruluk
/// Firestore/sunucu lifecycle'ıdır. Fingerprint / IP / login KULLANILMAZ;
/// anahtar yalnızca (tahmini) immutable linkId'dir.
class SubmittedMarker {
  static String keyFor(String linkId) => 'feedback2me_submitted_$linkId';

  /// Bu tarayıcı bu linke daha önce başarıyla yanıt verdi mi.
  /// Storage okunamazsa (private mode / plugin yok) `false` döner → akış bozulmaz.
  static Future<bool> has(String linkId) async {
    if (linkId.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keyFor(linkId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Başarılı submit sonrası çağrılır. Storage yazılamazsa sessizce yutulur.
  static Future<void> write(String linkId) async {
    if (linkId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyFor(linkId), true);
    } catch (_) {/* yut */}
  }
}
