import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../app_state.dart';
import '../config/iap_products.dart';
import '../l10n/app_localizations.dart';

/// Premium link kredisi satin alma ekrani: App Store / Google Play (IAP).
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _loading = true;
  String? _error;
  bool _purchasing = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadProducts();
      });
    }
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await iapService.loadProducts();
      final storeAvailable = await iapService.isStoreAvailable;
      if (!mounted) return;
      final credit = iapService.productById(IapProducts.premiumLinkSingle);
      setState(() {
        _loading = false;
        if (!storeAvailable) {
          _error = L10n.get(context, 'iapStoreUnavailable');
        } else if (credit == null) {
          _error = L10n.get(context, 'iapProductsComingSoon');
        } else {
          _error = null;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = L10n.get(context, 'iapLoadError');
        });
      }
    }
  }

  Future<void> _purchase(ProductDetails product) async {
    final uid = authService.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.get(context, 'iapLoginRequired'))),
      );
      return;
    }
    setState(() => _purchasing = true);
    try {
      final ok = await iapService.startPurchase(product);
      if (!mounted) return;
      setState(() => _purchasing = false);
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.get(context, 'iapPaymentOpened'))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.get(context, 'iapPurchaseStartFailed'))),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _purchasing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.get(context, 'errorGeneric').replaceAll('{e}', '$e'),
            ),
          ),
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
          SnackBar(content: Text(L10n.get(context, 'iapRestoreDone'))),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _restoring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.get(context, 'iapRestoreError').replaceAll('{e}', '$e'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = authService.uid;
    final credit = iapService.productById(IapProducts.premiumLinkSingle);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.get(context, 'iapScreenTitle')),
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
                    L10n.get(context, 'iapHeadline'),
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    L10n.get(context, 'iapBullets'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  if (kIsWeb)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          L10n.get(context, 'iapPaymentsNote'),
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
                                label: Text(L10n.get(context, 'retry')),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      if (credit != null)
                        _PurchaseCard(
                          title: L10n.get(context, 'iapCreditTitle'),
                          subtitle: L10n.get(context, 'iapCreditSubtitle'),
                          price: credit.price,
                          busy: _purchasing,
                          onPressed: _purchasing
                              ? null
                              : () => _purchase(credit),
                        )
                      else
                        _MissingProductRow(
                          label: IapProducts.premiumLinkSingle,
                          theme: theme,
                        ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _restoring ? null : _restore,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white54,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _restoring
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(L10n.get(context, 'iapRestoreButton')),
                      ),
                    ],
                    if (!kIsWeb &&
                        defaultTargetPlatform == TargetPlatform.iOS &&
                        !_loading &&
                        _error == null) ...[
                      const SizedBox(height: 22),
                      Text(
                        L10n.get(context, 'iapAppleFootnote'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white54,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (!kIsWeb &&
                        defaultTargetPlatform == TargetPlatform.android &&
                        !_loading &&
                        _error == null) ...[
                      const SizedBox(height: 22),
                      Text(
                        L10n.get(context, 'iapAndroidFootnote'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white54,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (kDebugMode) ...[
                      const SizedBox(height: 20),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 8),
                      Text(
                        L10n.get(context, 'iapDebugSection'),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: Colors.white38),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: uid == null
                            ? null
                            : () async {
                                final profile =
                                    await appData.getUserProfile(uid);
                                if (profile == null) return;
                                await appData.setUserProfile(
                                  uid,
                                  profile.copyWith(
                                    paidLinkCredits:
                                        profile.paidLinkCredits + 1,
                                  ),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Test: +1 link credit'),
                                    ),
                                  );
                                }
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white38,
                        ),
                        child: const Text('Test: +1 link credit'),
                      ),
                    ],
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

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.busy,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final String price;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: Colors.white.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 12),
            Text(
              price,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(L10n.get(context, 'iapBuy')),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingProductRow extends StatelessWidget {
  const _MissingProductRow({
    required this.label,
    required this.theme,
  });

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        L10n.get(context, 'iapNotInStore').replaceAll('{label}', label),
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.orangeAccent),
      ),
    );
  }
}
