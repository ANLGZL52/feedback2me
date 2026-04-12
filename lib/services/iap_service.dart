import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../app_state.dart';
import '../config/iap_products.dart';
import '../models/user_profile.dart';

/// App Store / Google Play IAP.
/// [purchaseStream] dinleyicisi uygulama açılır açılmaz ([IapService] oluşturulunca) kayıtlı olmalı.
class IapService {
  IapService() {
    if (!kIsWeb) _listenToPurchases();
  }

  final List<ProductDetails> _products = [];
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// Aynı işlem tekrar gelirse çifte teslimatı önlemek için (yenileme yeni purchaseID ile gelir).
  final Set<String> _deliveredKeys = <String>{};

  bool _available = false;

  bool get isAvailable => _available;

  List<ProductDetails> get loadedProducts => List.unmodifiable(_products);

  Set<String> notFoundProductIds = {};

  Future<bool> get isStoreAvailable async {
    if (kIsWeb) return false;
    _available = await InAppPurchase.instance.isAvailable();
    return _available;
  }

  ProductDetails? productById(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Ürünleri mağazadan yükle; aynı id için (Android abonelik teklifleri) ilk kayıt tutulur.
  Future<List<ProductDetails>> loadProducts() async {
    if (kIsWeb) return [];
    if (!await isStoreAvailable) return [];
    final response = await InAppPurchase.instance.queryProductDetails(
      IapProducts.all,
    );
    notFoundProductIds = response.notFoundIDs.toSet();
    _products.clear();
    final byId = <String, ProductDetails>{};
    for (final p in response.productDetails) {
      byId.putIfAbsent(p.id, () => p);
    }
    _products.addAll(byId.values);
    return List.from(_products);
  }

  void _listenToPurchases() {
    if (kIsWeb) return;
    _subscription?.cancel();
    _subscription = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdates,
      onDone: () => _subscription = null,
      onError: (Object e, StackTrace st) {
        debugPrint('IAP purchaseStream error: $e\n$st');
      },
    );
  }

  String _deliveryKey(PurchaseDetails p) {
    final pid = p.purchaseID;
    if (pid != null && pid.isNotEmpty) {
      return '${p.productID}|$pid';
    }
    final token = p.verificationData.serverVerificationData;
    if (token.isNotEmpty) return '${p.productID}|$token';
    return '${p.productID}|${p.transactionDate ?? 'unknown'}';
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) continue;

      if (purchase.status == PurchaseStatus.error) {
        debugPrint(
          'IAP error: ${purchase.error?.code} ${purchase.error?.message}',
        );
        if (purchase.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchase);
        }
        continue;
      }

      if (purchase.status == PurchaseStatus.canceled) {
        if (purchase.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchase);
        }
        continue;
      }

      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }

      final key = _deliveryKey(purchase);
      final fresh = !_deliveredKeys.contains(key);

      if (fresh) {
        try {
          if (purchase.productID == IapProducts.premiumMonthly) {
            await _grantPremiumToCurrentUser();
          } else if (purchase.productID == IapProducts.premiumLinkSingle) {
            await _grantLinkCreditToCurrentUser();
          } else {
            debugPrint('IAP: bilinmeyen ürün ${purchase.productID}');
          }
          _deliveredKeys.add(key);
        } catch (e, st) {
          debugPrint('IAP teslimat hatası: $e\n$st');
        }
      }

      if (purchase.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(purchase);
        } catch (e, st) {
          debugPrint('IAP completePurchase: $e\n$st');
        }
      }
    }
  }

  DateTime _extendedPremiumUntil(UserProfile profile) {
    final now = DateTime.now();
    final current = profile.premiumUntil;
    final anchor =
        current != null && current.isAfter(now) ? current : now;
    return anchor.add(const Duration(days: 30));
  }

  Future<void> _grantPremiumToCurrentUser() async {
    final uid = authService.uid;
    if (uid == null) return;
    final existing = await appData.getUserProfile(uid);
    final profile = existing ?? UserProfile(uid: uid);
    await appData.setUserProfile(
      uid,
      profile.copyWith(
        isPremium: true,
        premiumUntil: _extendedPremiumUntil(profile),
      ),
    );
  }

  Future<void> _grantLinkCreditToCurrentUser() async {
    final uid = authService.uid;
    if (uid == null) return;
    final existing = await appData.getUserProfile(uid);
    final profile = existing ?? UserProfile(uid: uid);
    await appData.setUserProfile(
      uid,
      profile.copyWith(
        paidLinkCredits: profile.paidLinkCredits + 1,
      ),
    );
  }

  /// Abonelik veya tüketilebilir — doğru [buyNonConsumable] / [buyConsumable] seçilir.
  Future<bool> startPurchase(ProductDetails product) async {
    if (kIsWeb) return false;
    final uid = authService.uid;
    if (uid == null) return false;
    final param = PurchaseParam(
      productDetails: product,
      applicationUserName: uid,
    );
    if (IapProducts.isConsumable(product.id)) {
      return InAppPurchase.instance.buyConsumable(
        purchaseParam: param,
        autoConsume: true,
      );
    }
    return InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restorePurchases() async {
    if (kIsWeb) return;
    final uid = authService.uid;
    await InAppPurchase.instance.restorePurchases(
      applicationUserName: uid,
    );
  }

  void dispose() {
    _subscription?.cancel();
  }
}
