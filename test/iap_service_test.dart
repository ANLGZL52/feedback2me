import 'package:flutter_test/flutter_test.dart';
import 'package:feedback_to_me/services/iap_service.dart';

// Unit tests for the server-authoritative purchase path. The client NEVER grants
// credit locally — it calls iapVerify and maps the verified server outcome. The
// callable is injected (IapVerifyFn) so these run without Firebase/platform
// channels. `listen:false` skips the purchase-stream subscription.
void main() {
  IapService make(IapVerifyFn verify, {String? uid = 'u1'}) =>
      IapService(verify: verify, uidProvider: () => uid, listen: false);

  group('IapService.verifyAndGrant — server-authoritative, no client-side grant', () {
    test('ok:true -> granted', () async {
      final s = make((req) async => {'ok': true});
      expect(await s.verifyAndGrant('premium_link_single', 'V', 't'), IapVerifyOutcome.granted);
    });

    test('ok:true + alreadyProcessed -> alreadyProcessed (replay grants +0)', () async {
      final s = make((req) async => {'ok': true, 'alreadyProcessed': true});
      expect(await s.verifyAndGrant('premium_link_single', 'V', 't'), IapVerifyOutcome.alreadyProcessed);
    });

    test('ok:false -> rejected (no credit)', () async {
      final s = make((req) async => {'ok': false});
      expect(await s.verifyAndGrant('premium_link_single', 'V', 't'), IapVerifyOutcome.rejected);
    });

    test('permanent verify failure -> rejected (consume, no credit)', () async {
      final s = make((req) async => throw IapVerifyException('permission-denied', permanent: true));
      expect(await s.verifyAndGrant('premium_link_single', 'V', 't'), IapVerifyOutcome.rejected);
    });

    test('transient verify failure -> rethrows (purchase stays queued, retried)', () async {
      final s = make((req) async => throw IapVerifyException('unavailable', permanent: false));
      expect(() => s.verifyAndGrant('premium_link_single', 'V', 't'), throwsA(isA<IapVerifyException>()));
    });

    test('not signed in -> StateError, no grant', () async {
      final s = make((req) async => {'ok': true}, uid: null);
      expect(() => s.verifyAndGrant('premium_link_single', 'V', 't'), throwsA(isA<StateError>()));
    });

    test('request carries store material only; client never sends a credit amount', () async {
      Map<String, dynamic>? seen;
      final s = make((req) async {
        seen = req;
        return {'ok': true};
      });
      await s.verifyAndGrant('premium_link_single', 'VERIFY_DATA', 'tx1');
      expect(seen!['productId'], 'premium_link_single');
      expect(seen!['verificationData'], 'VERIFY_DATA');
      expect(seen!['transactionId'], 'tx1');
      expect(seen!.containsKey('platform'), true);
      // The server allow-list determines the credit amount — the client must not.
      expect(seen!.containsKey('credit'), false);
      expect(seen!.containsKey('paidLinkCredits'), false);
    });
  });
}
