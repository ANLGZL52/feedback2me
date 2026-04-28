import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../app_state.dart';
import '../config/iap_products.dart';
import '../models/user_profile.dart';

/// App Store / Google Play IAP — sadece consumable (link basina odeme).
class IapService {
  IapService() {
    if (!kIsWeb) _listenToPurchases();
  }

  final List<ProductDetails> _products = [];
  StreamSubscription<List<PurchaseDetails>>? _purchaseUpdatesSub;

  final Set<String> _deliveredKeys = <String>{};

  bool _available = false;
  String? lastLoadError;

  bool get isAvailable => _available;

  List<ProductDetails> get loadedProducts => List.unmodifiable(_products);

  Set<String> notFoundProductIds = {};

  Future<bool> get isStoreAvailable async {
    if (kIsWeb) return false;
    try {
      _available = await InAppPurchase.instance.isAvailable();
    } catch (e) {
      debugPrint('IAP isAvailable error: $e');
      _available = false;
    }
    return _available;
  }

  ProductDetails? productById(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<List<ProductDetails>> loadProducts() async {
    if (kIsWeb) return [];
    lastLoadError = null;
    if (!await isStoreAvailable) {
      lastLoadError = 'store_unavailable';
      return [];
    }
    try {
      final response = await InAppPurchase.instance.queryProductDetails(
        IapProducts.all,
      );
      notFoundProductIds = response.notFoundIDs.toSet();
      if (response.error != null) {
        debugPrint('IAP queryProductDetails error: ${response.error}');
        lastLoadError = 'query_error';
      }
      _products.clear();
      final byId = <String, ProductDetails>{};
      for (final p in response.productDetails) {
        byId.putIfAbsent(p.id, () => p);
      }
      _products.addAll(byId.values);
      if (_products.isEmpty && notFoundProductIds.isNotEmpty) {
        lastLoadError = 'products_not_found';
      }
      return List.from(_products);
    } catch (e, st) {
      debugPrint('IAP loadProducts exception: $e\n$st');
      lastLoadError = 'load_exception';
      return [];
    }
  }

  void _listenToPurchases() {
    if (kIsWeb) return;
    _purchaseUpdatesSub?.cancel();
    _purchaseUpdatesSub = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdates,
      onDone: () => _purchaseUpdatesSub = null,
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
          if (purchase.productID == IapProducts.premiumLinkSingle) {
            await _grantLinkCreditToCurrentUser();
          } else {
            debugPrint('IAP: unknown product ${purchase.productID}');
          }
          _deliveredKeys.add(key);
        } catch (e, st) {
          debugPrint('IAP delivery error: $e\n$st');
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

  /// Consumable satin alma (link kredisi).
  Future<bool> startPurchase(ProductDetails product) async {
    if (kIsWeb) return false;
    final uid = authService.uid;
    if (uid == null) return false;
    if (!_available) {
      debugPrint('IAP: store not available, cannot purchase');
      return false;
    }
    final param = PurchaseParam(
      productDetails: product,
      applicationUserName: uid,
    );
    try {
      return await InAppPurchase.instance.buyConsumable(
        purchaseParam: param,
        autoConsume: true,
      );
    } catch (e, st) {
      debugPrint('IAP startPurchase error: $e\n$st');
      rethrow;
    }
  }

  Future<void> restorePurchases() async {
    if (kIsWeb) return;
    final uid = authService.uid;
    try {
      await InAppPurchase.instance.restorePurchases(
        applicationUserName: uid,
      );
    } catch (e, st) {
      debugPrint('IAP restorePurchases error: $e\n$st');
      rethrow;
    }
  }

  void dispose() {
    _purchaseUpdatesSub?.cancel();
  }
}
