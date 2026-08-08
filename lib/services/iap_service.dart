import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../app_state.dart';
import '../config/iap_products.dart';

/// App Store / Google Play IAP — sadece consumable (link basina odeme).
class IapService {
  IapService() {
    if (!kIsWeb) _listenToPurchases();
  }

  final List<ProductDetails> _products = [];
  StreamSubscription<List<PurchaseDetails>>? _purchaseUpdatesSub;

  final Set<String> _deliveredKeys = <String>{};

  /// Mağaza akışı veya [notifyLinkCreditGrantedForTesting] ile kredi işlendiğinde artar.
  final StreamController<int> _linkCreditGranted =
      StreamController<int>.broadcast();
  int _linkCreditGrantSeq = 0;

  /// Premium ekranı vb. dinleyebilir (başarılı +1 kredi teslimi).
  Stream<int> get onLinkCreditGranted => _linkCreditGranted.stream;

  void _emitLinkCreditGranted() {
    if (!_linkCreditGranted.isClosed) {
      _linkCreditGranted.add(++_linkCreditGrantSeq);
    }
  }

  /// Yerel test / debug: gerçek satın alma olmadan [onLinkCreditGranted] tetiklenir.
  void notifyLinkCreditGrantedForTesting() => _emitLinkCreditGranted();

  bool _available = false;
  String? lastLoadError;

  /// Son StoreKit / Play satın alma akışı hatası (sandbox dahil).
  String? lastPurchaseError;

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
        final code = purchase.error?.code ?? '';
        final msg = purchase.error?.message ?? '';
        lastPurchaseError = '$code $msg'.trim();
        debugPrint(
          'IAP error: $code $msg',
        );
        if (purchase.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchase);
        }
        continue;
      }

      if (purchase.status == PurchaseStatus.canceled) {
        lastPurchaseError = null;
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

      var shouldComplete = false;

      if (fresh) {
        try {
          if (purchase.productID == IapProducts.premiumLinkSingle) {
            await _verifyAndGrant(purchase);
            _emitLinkCreditGranted();
            _deliveredKeys.add(key);
            shouldComplete = true;
            lastPurchaseError = null;
          } else {
            debugPrint('IAP: unknown product ${purchase.productID}');
            _deliveredKeys.add(key);
            shouldComplete = true;
          }
        } catch (e, st) {
          debugPrint('IAP delivery error: $e\n$st');
          lastPurchaseError =
              'delivery_failed: $e';
          // Hesaba yazılamadıysa completePurchase yapma; işlem kuyrukta kalır.
          shouldComplete = false;
        }
      } else {
        shouldComplete = true;
      }

      if (purchase.pendingCompletePurchase && shouldComplete) {
        try {
          await InAppPurchase.instance.completePurchase(purchase);
        } catch (e, st) {
          debugPrint('IAP completePurchase: $e\n$st');
        }
      }
    }
  }

  /// Sunucu-yetkili kredi verme: mağaza makbuzunu Cloud Function `iapVerify`'e
  /// gönderir; kredi YALNIZCA sunucuda (Admin SDK) doğrulama sonrası yazılır.
  /// İstemci artık `paidLinkCredits`'i doğrudan yazmaz (firestore.rules kilitli).
  /// Yerel profil, Firestore stream'inden otomatik güncellenir.
  ///
  /// Hata fırlatırsa çağıran `completePurchase` yapmaz → işlem kuyrukta kalır,
  /// bir sonraki açılışta yeniden denenir (idempotent: sunucu replay'i engeller).
  Future<void> _verifyAndGrant(PurchaseDetails purchase) async {
    final uid = authService.uid;
    if (uid == null) {
      throw StateError('not_signed_in');
    }
    final platform =
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    final callable = FirebaseFunctions.instance.httpsCallable('iapVerify');
    final res = await callable.call(<String, dynamic>{
      'platform': platform,
      'productId': purchase.productID,
      'verificationData': purchase.verificationData.serverVerificationData,
      'transactionId': purchase.purchaseID,
    });
    final data = res.data;
    final ok = data is Map && data['ok'] == true;
    if (!ok) {
      throw StateError('verify_failed');
    }
  }

  /// Consumable satin alma (link kredisi).
  Future<bool> startPurchase(ProductDetails product) async {
    if (kIsWeb) return false;
    final uid = authService.uid;
    if (uid == null) return false;
    lastPurchaseError = null;
    if (!_available) {
      debugPrint('IAP: store not available, cannot purchase');
      lastPurchaseError = 'store_unavailable';
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
      lastPurchaseError = e.toString();
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
