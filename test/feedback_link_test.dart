import 'package:flutter_test/flutter_test.dart';
import 'package:feedback_to_me/models/feedback_link.dart';

FeedbackLink _link({
  bool isActive = true,
  DateTime? validUntil,
  String? tier,
  bool demoUsed = false,
}) =>
    FeedbackLink(
      id: 'id',
      ownerId: 'owner',
      code: 'abc',
      isActive: isActive,
      validUntil: validUntil,
      linkTier: tier,
      demoSubmissionUsed: demoUsed,
    );

void main() {
  group('FeedbackLink.isLive / remaining (U1)', () {
    test('validUntil gelecekte + aktif → isLive true, remaining > 0', () {
      final l = _link(validUntil: DateTime.now().add(const Duration(hours: 5)), tier: 'premium');
      expect(l.isLive, isTrue);
      expect(l.isPastValidWindow, isFalse);
      expect(l.remaining.inMinutes, greaterThan(0));
    });

    test('validUntil geçmişte + aktif → isLive false, remaining zero', () {
      final l = _link(validUntil: DateTime.now().subtract(const Duration(minutes: 1)), tier: 'premium');
      expect(l.isPastValidWindow, isTrue);
      expect(l.isLive, isFalse);
      expect(l.remaining, Duration.zero);
    });

    test('isActive false → isLive false (validUntil ne olursa olsun)', () {
      final l = _link(isActive: false, validUntil: DateTime.now().add(const Duration(hours: 5)));
      expect(l.isLive, isFalse);
    });

    test('validUntil null (legacy) → isPastValidWindow false, isLive == isActive', () {
      final live = _link(validUntil: null); // isActive true
      expect(live.isPastValidWindow, isFalse);
      expect(live.isLive, isTrue);
      expect(live.remaining, Duration.zero); // legacy: geri sayım yok

      final closed = _link(isActive: false, validUntil: null);
      expect(closed.isLive, isFalse);
    });

    test('displayPlan tier eşlemesi (kart etiketi için)', () {
      expect(_link(tier: 'premium').displayPlan, FeedbackLinkPlan.premium);
      expect(_link(tier: 'demo').displayPlan, FeedbackLinkPlan.demo);
      expect(_link(tier: null).displayPlan, FeedbackLinkPlan.legacy);
    });
  });
}
