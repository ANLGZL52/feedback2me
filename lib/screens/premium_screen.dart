import 'dart:async';

import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../app_state.dart';
import '../config/iap_products.dart';
import '../design_system/design_system.dart';
import '../l10n/app_localizations.dart';
import '../models/user_profile.dart';
import '../widgets/premium/premium_widgets.dart';

/// Premium link kredisi satın alma ekranı: App Store / Google Play (IAP).
/// V2 aydınlık; IAP mantığı (yükleme/satın alma/geri yükleme/grant) korunur.
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
  StreamSubscription<int>? _creditGrantedSub;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadProducts();
      });
      _creditGrantedSub = iapService.onLinkCreditGranted.listen((_) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.get(context, 'iapCreditGrantedSnack')),
            ),
          );
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _creditGrantedSub?.cancel();
    super.dispose();
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
      await iapService.loadProducts();
      if (!mounted) return;
      final fresh = iapService.productById(IapProducts.premiumLinkSingle);
      if (fresh == null) {
        setState(() {
          _purchasing = false;
          _error = L10n.get(context, 'iapProductsComingSoon');
        });
        return;
      }
      final ok = await iapService.startPurchase(fresh);
      if (!mounted) return;
      setState(() => _purchasing = false);
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.get(context, 'iapPaymentOpened'))),
        );
      } else {
        final err = iapService.lastPurchaseError;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              err != null && err.isNotEmpty
                  ? L10n.get(context, 'iapPurchaseStartFailedWithDetail')
                      .replaceAll('{detail}', err)
                  : L10n.get(context, 'iapPurchaseStartFailed'),
            ),
          ),
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
    final uid = authService.uid;
    final oid = uid != null ? (effectiveDataOwnerId(uid) ?? uid) : null;
    final credit = iapService.productById(IapProducts.premiumLinkSingle);

    return FeedbackScaffold(
      maxWidth: AppSpacing.maxWidthPremium,
      appBar: feedbackAppBar(context, title: L10n.get(context, 'iapScreenTitle')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
        children: [
          _hero(context),
          const SizedBox(height: AppSpacing.l),
          if (oid != null)
            StreamBuilder<UserProfile?>(
              stream: appData.userProfileStream(oid),
              builder: (context, snap) {
                final p = snap.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CreditBalanceCard(
                      credits: p?.paidLinkCredits ?? 0,
                      activePremium: p?.hasActivePremium ?? false,
                    ),
                    const SizedBox(height: AppSpacing.l),
                    _comparison(context, demoUsed: p?.freeDemoLinkUsed ?? false),
                  ],
                );
              },
            )
          else
            _comparison(context, demoUsed: false),
          const SizedBox(height: AppSpacing.l),
          _purchaseSection(context, credit),
          const SizedBox(height: AppSpacing.l),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: AppRadius.rLarge,
            boxShadow: AppShadows.primaryGlow,
          ),
          child: const Icon(Icons.workspace_premium_rounded,
              color: AppColors.onPrimary, size: 38),
        ),
        const SizedBox(height: AppSpacing.m),
        Text(L10n.get(context, 'premiumV2Title'),
            style: AppType.display, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.s),
        Text(L10n.get(context, 'premiumV2Subtitle'),
            style: AppType.secondary, textAlign: TextAlign.center),
      ],
    );
  }

  Widget _comparison(BuildContext context, {required bool demoUsed}) {
    final demo = PlanCompareCard(
      title: L10n.get(context, 'tierDemo'),
      priceLabel: L10n.get(context, 'tierFree'),
      highlighted: false,
      icon: Icons.science_rounded,
      badge: demoUsed ? L10n.get(context, 'premiumV2DemoUsed') : null,
      features: [
        L10n.get(context, 'tierDemoF1'),
        L10n.get(context, 'tierDemoF2'),
        L10n.get(context, 'tierDemoF3'),
      ],
    );
    final premium = PlanCompareCard(
      title: L10n.get(context, 'premiumV2PremiumLink'),
      priceLabel: '1 ${L10n.get(context, 'premiumV2CreditSingular')}',
      highlighted: true,
      icon: Icons.workspace_premium_rounded,
      badge: null,
      features: [
        L10n.get(context, 'tierPremiumF1'),
        L10n.get(context, 'tierPremiumF2'),
        L10n.get(context, 'tierPremiumF3'),
      ],
    );
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 560) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: demo),
              const SizedBox(width: AppSpacing.m),
              Expanded(child: premium),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            demo,
            const SizedBox(height: AppSpacing.m),
            premium,
          ],
        );
      },
    );
  }

  Widget _purchaseSection(BuildContext context, ProductDetails? credit) {
    if (kIsWeb) {
      return FeedbackCard(
        color: AppColors.primarySoft,
        shadow: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.smartphone_rounded,
                color: AppColors.primary, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(L10n.get(context, 'iapPaymentsNote'),
                  style: AppType.secondary),
            ),
          ],
        ),
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: FeedbackLoadingState(),
      );
    }
    if (_error != null) {
      return FeedbackErrorState(
        message: _error!,
        retryLabel: L10n.get(context, 'retry'),
        onRetry: _loadProducts,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (credit != null)
          PurchaseCardV2(
            title: L10n.get(context, 'iapCreditTitle'),
            subtitle: L10n.get(context, 'iapCreditSubtitle'),
            price: credit.price,
            busy: _purchasing,
            onPressed: _purchasing ? null : () => _purchase(credit),
          )
        else
          Text(
            L10n.get(context, 'iapNotInStore')
                .replaceAll('{label}', IapProducts.premiumLinkSingle),
            style: AppType.secondary.copyWith(color: AppColors.warning),
          ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: FeedbackTextButton(
            label: _restoring
                ? '…'
                : L10n.get(context, 'iapRestoreButton'),
            onPressed: _restoring ? null : _restore,
            color: AppColors.textSecondary,
          ),
        ),
        if (defaultTargetPlatform == TargetPlatform.iOS) ...[
          const SizedBox(height: AppSpacing.m),
          Text(L10n.get(context, 'iapAppleFootnote'), style: AppType.caption),
        ],
        if (defaultTargetPlatform == TargetPlatform.android) ...[
          const SizedBox(height: AppSpacing.m),
          Text(L10n.get(context, 'iapAndroidFootnote'), style: AppType.caption),
        ],
        // NOTE: the debug "Test: +1 link credit" button was removed during the
        // V2+hardened reconciliation. It wrote paidLinkCredits CLIENT-SIDE, which
        // the hardened IAP model forbids — credit is granted ONLY server-side by
        // the iapVerify Cloud Function after a verified store purchase.
      ],
    );
  }
}
