import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../app_state.dart';
import '../models/user_profile.dart';

/// Premium abonelik: App Store / Google Play üzerinden (IAP).
/// Web'de satın alma yok; mobilde in_app_purchase ile satın alınır.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  List<ProductDetails> _products = [];
  bool _loading = true;
  String? _error;
  bool _purchasing = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await iapService.loadProducts();
      final storeAvailable = await iapService.isStoreAvailable;
      if (mounted) {
        setState(() {
          _products = list;
          _loading = false;
          if (list.isEmpty && !storeAvailable) {
            _error = 'Mağaza kullanılamıyor.';
          } else if (list.isEmpty) {
            _error = 'Ürün henüz mağazada tanımlı değil (premium_monthly).';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _purchase(ProductDetails product) async {
    final uid = authService.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce giriş yapmalısın.')),
      );
      return;
    }
    setState(() => _purchasing = true);
    try {
      final ok = await iapService.startPurchase(product);
      if (mounted) {
        setState(() => _purchasing = false);
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Satın alma başlatıldı. Ödeme tamamlanınca premium açılacak.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Satın alma başlatılamadı.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _purchasing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    try {
      await iapService.restorePurchases();
      if (mounted) {
        setState(() => _restoring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Satın alımlar kontrol edildi. Premium zaten varsa güncellenecek.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _restoring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Geri yükleme hatası: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = authService.uid;
    final product = _products.isNotEmpty ? _products.first : null;
    final priceLabel = product?.price ?? '99 ₺';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Premium'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Aylık Premium',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${product?.price ?? '99 ₺'} / ay',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '• Kişisel feedback linki oluştur\n'
                    '• Sınırsız link (aylık)\n'
                    '• AI ile rapor ve gelişim analizi\n'
                    '• Raporu görsel olarak paylaş',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  if (kIsWeb)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Premium satın alma Apple App Store ve Google Play Store '
                          'üzerinden yapılır. Lütfen uygulamayı telefonunda açıp '
                          'bu ekrandan abonelik satın al.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.white70),
                        ),
                      ),
                    )
                  else ...[
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_error != null)
                      Card(
                        color: Colors.white12,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _error!,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: Colors.white70),
                              ),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: _loadProducts,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Tekrar dene'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (product != null)
                      FilledButton(
                        onPressed: _purchasing
                            ? null
                            : () => _purchase(product),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _purchasing
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text('$priceLabel — Aylık premium satın al'),
                      )
                    else
                      FilledButton(
                        onPressed: _loadProducts,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Ürünü yükle'),
                      ),
                    const SizedBox(height: 12),
                    if (product != null)
                      OutlinedButton(
                        onPressed: _restoring ? null : _restore,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white54,
                        ),
                        child: _restoring
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Satın alımı geri yükle'),
                      ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: uid == null
                          ? null
                          : () async {
                              final profile =
                                  await appData.getUserProfile(uid);
                              if (profile == null) return;
                              final until =
                                  DateTime.now().add(const Duration(days: 30));
                              await appData.setUserProfile(
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
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Premium test için açıldı (30 gün)')),
                                );
                                Navigator.of(context).pop();
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white38,
                      ),
                      child: const Text(
                          'Test: Premium\'u 30 gün aç (geliştirme)'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
