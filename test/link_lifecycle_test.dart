// Production feedback lifecycle invariant KİLİDİ (model seviyesi).
// acceptsPublicFeedback / isPastValidWindow semantiği: süre + tek-kullanım +
// expiry + inactive. Production logic DEĞİŞTİRİLMEDEN mevcut davranış kilitlenir;
// biri limitleri gevşetirse bu testler kırılır.

import 'package:flutter_test/flutter_test.dart';
import 'package:feedback_to_me/models/feedback_link.dart';

FeedbackLink _link({
  String? tier = 'demo',
  bool isActive = true,
  DateTime? validUntil,
  bool demoUsed = false,
}) =>
    FeedbackLink(
      id: 'l1',
      ownerId: 'o1',
      code: 'abc123',
      isActive: isActive,
      linkTier: tier,
      validUntil: validUntil,
      demoSubmissionUsed: demoUsed,
    );

void main() {
  final now = DateTime.now();

  group('Demo lifecycle', () {
    test('created → active kabul eder', () {
      final l = _link(validUntil: now.add(const Duration(minutes: 10)));
      expect(l.isDemoTier, isTrue);
      expect(l.displayPlan, FeedbackLinkPlan.demo);
      expect(l.isActive, isTrue);
      expect(l.acceptsPublicFeedback, isTrue);
    });

    test('süre içinde (t<10:00) → kabul', () {
      final l = _link(validUntil: now.add(const Duration(seconds: 1)));
      expect(l.isPastValidWindow, isFalse);
      expect(l.acceptsPublicFeedback, isTrue);
    });

    test('süre dolmuş (t>=10:00) → red', () {
      final l = _link(validUntil: now.subtract(const Duration(seconds: 1)));
      expect(l.isPastValidWindow, isTrue);
      expect(l.acceptsPublicFeedback, isFalse);
    });

    test('ilk submit sonrası demoSubmissionUsed=true → red (tek yorum)', () {
      final l = _link(
          validUntil: now.add(const Duration(minutes: 10)), demoUsed: true);
      expect(l.acceptsPublicFeedback, isFalse);
    });

    test('ilk submit sonrası isActive=false → red', () {
      final l = _link(
          validUntil: now.add(const Duration(minutes: 10)), isActive: false);
      expect(l.acceptsPublicFeedback, isFalse);
    });

    test('süre içinde ama zaten kullanılmış (used) → red', () {
      final l = _link(
          validUntil: now.add(const Duration(minutes: 5)),
          demoUsed: true,
          isActive: false);
      expect(l.acceptsPublicFeedback, isFalse);
    });
  });

  group('Premium lifecycle', () {
    test('t<24h → kabul', () {
      final l = _link(
          tier: 'premium',
          validUntil: now.add(const Duration(hours: 23, minutes: 59)));
      expect(l.isPremiumTier, isTrue);
      expect(l.displayPlan, FeedbackLinkPlan.premium);
      expect(l.acceptsPublicFeedback, isTrue);
    });

    test('çoklu farklı-yanıtlayıcı business modelde allowed '
        '(premium demoSubmissionUsed alanı kapıyı ETKİLEMEZ)', () {
      // Premium linkte demoSubmissionUsed set olsa bile demo değil → limit yok;
      // 24 saat boyunca çoklu feedback kabul edilir.
      final l = _link(
          tier: 'premium',
          validUntil: now.add(const Duration(hours: 1)),
          demoUsed: true);
      expect(l.acceptsPublicFeedback, isTrue);
    });

    test('t>=24h → red', () {
      final l = _link(
          tier: 'premium',
          validUntil: now.subtract(const Duration(seconds: 1)));
      expect(l.acceptsPublicFeedback, isFalse);
    });

    test('expired premium yeniden aktifleşemez '
        '(isActive=true olsa bile geçmiş validUntil kapıyı kapatır)', () {
      final reactivatedFlag = _link(
          tier: 'premium',
          isActive: true,
          validUntil: now.subtract(const Duration(hours: 1)));
      expect(reactivatedFlag.acceptsPublicFeedback, isFalse);
    });
  });

  group('Legacy (tier alanı yok)', () {
    test('linkTier null → süre/tek-kullanım yok; aktifse kabul', () {
      final l = FeedbackLink(id: 'l', ownerId: 'o', code: 'c');
      expect(l.displayPlan, FeedbackLinkPlan.legacy);
      expect(l.acceptsPublicFeedback, isTrue);
    });
  });

  group('Persistence — süre mutlak validUntil\'a bağlı (refresh/restart reset ETMEZ)', () {
    test('map\'ten yüklenen demo: validUntil=created+10dk geçmişse → dolmuş', () {
      // "App restart / refresh" simülasyonu: link map'ten yeniden kurulur.
      // Süre createdAt\'e göre YENİDEN saymaz; mutlak validUntil geçerlidir.
      final createdLongAgo = now.subtract(const Duration(minutes: 20));
      final map = {
        'ownerId': 'o',
        'code': 'c',
        'createdAt': createdLongAgo.toIso8601String(),
        'isActive': true,
        'linkTier': 'demo',
        'validUntil':
            createdLongAgo.add(const Duration(minutes: 10)).toIso8601String(),
        'demoSubmissionUsed': false,
      };
      final l = FeedbackLink.fromMap('l', map);
      // validUntil = (now-20dk)+10dk = now-10dk → DOLMUŞ; refresh sıfırlamaz.
      expect(l.isPastValidWindow, isTrue);
      expect(l.acceptsPublicFeedback, isFalse);
    });

    test('map\'ten yüklenen premium: validUntil ileride → hâlâ aktif', () {
      final map = {
        'ownerId': 'o',
        'code': 'c',
        'isActive': true,
        'linkTier': 'premium',
        'validUntil': now.add(const Duration(hours: 5)).toIso8601String(),
        'demoSubmissionUsed': false,
      };
      final l = FeedbackLink.fromMap('l', map);
      expect(l.acceptsPublicFeedback, isTrue);
    });

    test('countdown kaynağı gerçek validUntil (map round-trip korunur)', () {
      final vu = now.add(const Duration(hours: 24));
      final l = _link(tier: 'premium', validUntil: vu);
      final reloaded = FeedbackLink.fromMap('l', l.toMap());
      expect(reloaded.validUntil!.toIso8601String(), vu.toIso8601String());
    });
  });
}
