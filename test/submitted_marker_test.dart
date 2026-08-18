// Same-browser anti-repeat marker (SubmittedMarker) — §23.
// UX caydırıcı; server lifecycle'ını ETKİLEMEZ. Marker YALNIZ başarılı submit
// sonrası yazılır (bunu FeedbackFormScreen._submit çağırır). Burada saf
// storage davranışı doğrulanır.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:feedback_to_me/services/submitted_marker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('1) marker yok → has() false (form gösterilir)', () async {
    expect(await SubmittedMarker.has('linkA'), isFalse);
  });

  test('2) başarılı submit (write) sonrası → has() true (form gizlenir)',
      () async {
    await SubmittedMarker.write('linkA');
    expect(await SubmittedMarker.has('linkA'), isTrue);
  });

  test('3) marker key formatı linkId bazlı ve stabil', () {
    expect(SubmittedMarker.keyFor('abc'), 'feedback2me_submitted_abc');
  });

  test('4) farklı link bağımsız → biri diğerini engellemez', () async {
    await SubmittedMarker.write('linkA');
    expect(await SubmittedMarker.has('linkA'), isTrue);
    expect(await SubmittedMarker.has('linkB'), isFalse); // farklı link allowed
  });

  test('5) boş linkId → yazmaz/okumaz, crash yok (guard)', () async {
    await SubmittedMarker.write('');
    expect(await SubmittedMarker.has(''), isFalse);
  });

  test('6) marker per-link/local — premium global kapanışını temsil ETMEZ',
      () async {
    // Marker yalnız yerel bir anahtardır; premium linkin 24 saat boyunca farklı
    // yanıtlayıcılardan (temiz storage) feedback almasını ENGELLEMEZ. Global
    // çoklu-feedback izni server rules testinde (6/6b) doğrulanır.
    await SubmittedMarker.write('premiumA');
    expect(await SubmittedMarker.has('premiumA'), isTrue);
    expect(await SubmittedMarker.has('premiumB'), isFalse);
  });
}
