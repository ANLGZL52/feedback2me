// Min-version gate saf karar mantığı (VersionGate.updateRequiredFor).
// Firestore okuma fail-open sarmalayıcıdır; burada yalnız karar test edilir.

import 'package:flutter_test/flutter_test.dart';
import 'package:feedback_to_me/config/app_build.dart';
import 'package:feedback_to_me/services/version_gate.dart';

void main() {
  group('VersionGate.updateRequiredFor', () {
    test('appBuild < min → true (güncelleme gerekli)', () {
      expect(VersionGate.updateRequiredFor(20, 25), isTrue);
    });
    test('appBuild == min → false', () {
      expect(VersionGate.updateRequiredFor(20, 20), isFalse);
    });
    test('appBuild > min → false', () {
      expect(VersionGate.updateRequiredFor(25, 20), isFalse);
    });
    test('min null (doc/alan yok / offline) → false (FAIL-OPEN)', () {
      expect(VersionGate.updateRequiredFor(20, null), isFalse);
    });
  });

  test('kAppBuild pozitif ve pubspec build ile senkron tutulmalı', () {
    expect(kAppBuild, greaterThan(0));
  });

  test('storeUrl boş değil (platforma göre mağaza)', () {
    expect(VersionGate.storeUrl().toString(), isNotEmpty);
  });
}
