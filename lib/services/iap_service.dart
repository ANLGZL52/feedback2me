import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../app_state.dart';
import '../models/user_profile.dart';

/// Premium aylık abonelik ürün ID'si (App Store Connect & Play Console'da aynı tanımlanmalı).
const String premiumProductId = 'premium_monthly';

/// App Store / Google Play IAP: ürün yükleme, satın alma, satın alımı geri yükleme.
/// Satın alma tamamlanınca Firestore'da isPremium / premiumUntil güncellenir.
class IapService {
  IapService() {
    if (!kIsWeb) _listenToPurchases();
  }

  final List<ProductDetails> _products = [];
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool get isAvailable => _available;
  bool _available = false;

  /// Mağaza kullanılabilir mi (mobil cihazda store bağlı).
  Future<bool> get isStoreAvailable async {
    if (kIsWeb) return false;
    _available = await InAppPurchase.instance.isAvailable();
    return _available;
  }

  /// Abonelik ürününü yükle (fiyat vb. için).
  Future<List<ProductDetails>> loadProducts() async {
    if (kIsWeb) return [];
    if (!await isStoreAvailable) return [];
    final response = await InAppPurchase.instance.queryProductDetails(
      {premiumProductId},
    );
    if (response.notFoundIDs.isNotEmpty) return [];
    _products.clear();
    _products.addAll(response.productDetails);
    return List.from(_products);
  }

  /// İlk ürün (premium_monthly) varsa döner.
  ProductDetails? get premiumProduct =>
      _products.isEmpty ? null : _products.first;

  void _listenToPurchases() {
    if (kIsWeb) return;
    _subscription?.cancel();
    _subscription = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdates,
      onDone: () => _subscription = null,
      onError: (_) {},
    );
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _grantPremiumToCurrentUser();
        await InAppPurchase.instance.completePurchase(purchase);
      }
      // pending / error / canceled için sadece completePurchase çağrılmaz
    }
  }

  /// Mevcut giriş yapmış kullanıcıya premium ver (1 ay).
  Future<void> _grantPremiumToCurrentUser() async {
    final uid = authService.uid;
    if (uid == null) return;
    final profile = await firestoreService.getUserProfile(uid);
    if (profile == null) return;
    final until = DateTime.now().add(const Duration(days: 30));
    await firestoreService.setUserProfile(
      uid,
      UserProfile(
        uid: uid,
        displayName: profile.displayName,
        email: profile.email,
        photoUrl: profile.photoUrl,
        handle: profile.handle,
        isPremium: true,
        premiumUntil: until,
        createdAt: profile.createdAt,
      ),
    );
  }

  /// Satın alma başlat (mobil, giriş yapılmış ve ürün yüklü olmalı).
  Future<bool> startPurchase(ProductDetails product) async {
    if (kIsWeb) return false;
    final uid = authService.uid;
    if (uid == null) return false;
    return InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: product,
        applicationUserName: uid,
      ),
    );
  }

  /// Satın alımları geri yükle (örn. yeni cihaz).
  Future<void> restorePurchases() async {
    if (kIsWeb) return;
    await InAppPurchase.instance.restorePurchases();
  }

  void dispose() {
    _subscription?.cancel();
  }
}
