import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../app_state.dart';
import '../config/iap_products.dart';

/// Sunucu-yetkili IAP doğrulama sonucu.
enum IapVerifyOutcome { granted, alreadyProcessed, rejected }

/// Test için enjekte edilebilir: `iapVerify` Cloud Function çağrısını temsil eder
/// (platform channel olmadan test edilebilsin diye). İstek → response Map.
typedef IapVerifyFn = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> request);

/// `iapVerify` hatası. [permanent]=true → makbuz kesin reddedildi (tekrar deneme);
/// false → geçici hata (ağ/sunucu) → satın alma kuyrukta kalır, sonra tekrar denenir.
class IapVerifyException implements Exception {
  IapVerifyException(this.code, {this.permanent = false});
  final String code;
  final bool permanent;
  @override
  String toString() => 'IapVerifyException($code, permanent: $permanent)';
}

/// App Store / Google Play IAP — sadece consumable (link basina odeme).
/// Kredi YALNIZCA sunucuda (iapVerify Cloud Function + Admin SDK) verilir; istemci
/// `paidLinkCredits`'i asla doğrudan yazmaz (firestore.rules kilitli).
class IapService {
  IapService({IapVerifyFn? verify, String? Function()? uidProvider, bool listen = true})
      : _verify = verify ?? _defaultVerify,
        _uidProvider = uidProvider ?? (() => authService.uid) {
    if (listen && !kIsWeb) _listenToPurchases();
  }

  final IapVerifyFn _verify;
  final String? Function() _uidProvider;

  /// Varsayılan doğrulama: `iapVerify` callable'ını çağırır. Kalıcı ret
  /// (permission-denied / invalid-argument) [IapVerifyException.permanent]=true olur.
  static Future<Map<String, dynamic>> _defaultVerify(
      Map<String, dynamic> req) async {
    try {
      final res =
          await FirebaseFunctions.instance.httpsCallable('iapVerify').call(req);
      final d = res.data;
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final permanent =
          e.code == 'permission-denied' || e.code == 'invalid-argument';
      throw IapVerifyException(e.code, permanent: permanent);
    }
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
        IapProducts.purchasable, // yeni istemci yalnızca v2 sorgular/satın alır
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
      // Mağazadan ürün yüklenemediyse (kullanıcı "kredi yüklenemedi" görür) izle.
      if (lastLoadError != null) {
        _reportNonFatal('iap_load_failed:$lastLoadError',
            {'notFound': notFoundProductIds.join(','), 'products': _products.length});
      }
      return List.from(_products);
    } catch (e, st) {
      debugPrint('IAP loadProducts exception: $e\n$st');
      lastLoadError = 'load_exception';
      _reportNonFatal('iap_load_exception', {'error': '$e'}, e, st);
      return [];
    }
  }

  /// Crashlytics'e ölümcül-olmayan hata bildir (yalnız mobil; best-effort).
  void _reportNonFatal(String reason, Map<String, Object?> info,
      [Object? error, StackTrace? st]) {
    if (kIsWeb) return;
    try {
      FirebaseCrashlytics.instance.recordError(
        error ?? reason,
        st,
        reason: reason,
        information: info.entries.map((e) => '${e.key}=${e.value}').toList(),
        fatal: false,
      );
    } catch (_) {}
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
          // v2 (yeni satın alma) VEYA eski premium_link_single (güncelleme sonrası
          // kurtarma). Her ikisi de SUNUCUDA (iapVerify) doğrulanır; istemci kredi
          // yazmaz. Yeni satın alma yalnızca v2 için BAŞLATILIR (startPurchase),
          // ama teslimat kanalı bekleyen eski işlemleri de kurtarır.
          if (IapProducts.isKnownCreditProduct(purchase.productID)) {
            final outcome = await verifyAndGrant(
              purchase.productID,
              purchase.verificationData.serverVerificationData,
              purchase.purchaseID,
            );
            if (outcome == IapVerifyOutcome.rejected) {
              // Makbuz mağaza tarafından KESIN reddedildi: kredi verilmez, tüketilir.
              debugPrint('IAP: verification rejected for ${purchase.productID}');
              lastPurchaseError = 'verify_rejected';
              _deliveredKeys.add(key);
              shouldComplete = true;
            } else {
              // granted VEYA alreadyProcessed → kredi sunucuda (Admin SDK) yazıldı.
              _emitLinkCreditGranted();
              _deliveredKeys.add(key);
              shouldComplete = true;
              lastPurchaseError = null;
            }
          } else {
            debugPrint('IAP: unknown product ${purchase.productID}');
            _deliveredKeys.add(key);
            shouldComplete = true;
          }
        } catch (e, st) {
          // Geçici hata (ağ / sunucu / giriş yok): completePurchase YAPMA. Satın
          // alma kuyrukta kalır, sonraki stream/açılışta tekrar denenir. Sunucu
          // idempotency çift-kredi'yi önler.
          debugPrint('IAP delivery error: $e\n$st');
          lastPurchaseError = 'delivery_failed: $e';
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

  /// Sunucu-yetkili kredi verme: mağaza makbuzunu `iapVerify` Cloud Function'a
  /// gönderir; kredi YALNIZCA sunucuda (Admin SDK) doğrulama sonrası yazılır.
  /// İstemci `paidLinkCredits`'i asla doğrudan yazmaz. Yerel profil Firestore
  /// stream'inden güncellenir. Sunucu idempotent olduğundan retry güvenlidir.
  ///
  /// Dönüş: granted (+1), alreadyProcessed (replay — kredi yok), rejected (kalıcı
  /// ret — kredi yok). Geçici hata → exception fırlatır (çağıran completePurchase
  /// yapmaz → kuyrukta kalır, tekrar denenir).
  @visibleForTesting
  Future<IapVerifyOutcome> verifyAndGrant(
      String productId, String verificationData, String? transactionId) async {
    final uid = _uidProvider();
    if (uid == null) throw StateError('not_signed_in'); // geçici: giriş sonrası retry
    final platform =
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    try {
      final data = await _verify(<String, dynamic>{
        'platform': platform,
        'productId': productId,
        'verificationData': verificationData,
        'transactionId': transactionId,
      });
      if (data['ok'] != true) {
        throw IapVerifyException('verify_failed', permanent: true);
      }
      return data['alreadyProcessed'] == true
          ? IapVerifyOutcome.alreadyProcessed
          : IapVerifyOutcome.granted;
    } on IapVerifyException catch (e) {
      if (e.permanent) return IapVerifyOutcome.rejected;
      rethrow; // geçici → satın almayı kuyrukta bırak, tekrar dene
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
