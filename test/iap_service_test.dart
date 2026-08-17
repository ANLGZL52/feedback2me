import 'package:flutter_test/flutter_test.dart';
import 'package:feedback_to_me/services/iap_service.dart';
import 'package:feedback_to_me/config/iap_products.dart';

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

    test('forwards the exact productId (v2 new purchase) unchanged', () async {
      Map<String, dynamic>? seen;
      final s = make((req) async {
        seen = req;
        return {'ok': true};
      });
      await s.verifyAndGrant(IapProducts.premiumLinkSingleV2, 'VERIFY_DATA', 'tx1');
      expect(seen!['productId'], 'premium_link_single_v2');
      expect(seen!['verificationData'], 'VERIFY_DATA');
      expect(seen!['transactionId'], 'tx1');
      expect(seen!.containsKey('platform'), true);
      // The server allow-list determines the credit amount — the client must not.
      expect(seen!.containsKey('credit'), false);
      expect(seen!.containsKey('paidLinkCredits'), false);
    });

    test('legacy product still verifies server-side (recovery of old transactions)', () async {
      Map<String, dynamic>? seen;
      final s = make((req) async {
        seen = req;
        return {'ok': true};
      });
      final out = await s.verifyAndGrant(IapProducts.premiumLinkSingle, 'V', 'legacyTx');
      expect(out, IapVerifyOutcome.granted);
      expect(seen!['productId'], 'premium_link_single');
    });
  });

  group('IapProducts — product-id migration (new buys v2; legacy recover only)', () {
    test('purchasable is v2 ONLY (new client never initiates a legacy purchase)', () {
      expect(IapProducts.purchasable, {'premium_link_single_v2'});
    });
    test('recoverable/isKnownCreditProduct accepts BOTH v2 and legacy', () {
      expect(IapProducts.isKnownCreditProduct('premium_link_single_v2'), true);
      expect(IapProducts.isKnownCreditProduct('premium_link_single'), true);
    });
    test('unknown product is not credit-bearing', () {
      expect(IapProducts.isKnownCreditProduct('premium_link_single_v3'), false);
      expect(IapProducts.isKnownCreditProduct('bogus'), false);
    });
  });
}
