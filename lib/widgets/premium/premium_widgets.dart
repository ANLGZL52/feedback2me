import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../l10n/app_localizations.dart';

/// Gerçek kredi bakiyesi (paidLinkCredits) — güçlü gradient kart.
class CreditBalanceCard extends StatelessWidget {
  const CreditBalanceCard(
      {super.key, required this.credits, required this.activePremium});

  final int credits;
  final bool activePremium;

  @override
  Widget build(BuildContext context) {
    return FeedbackCard(
      gradient: AppColors.primaryGradient,
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(L10n.get(context, 'premiumV2CreditBalance'),
                    style: AppType.bodyStrong
                        .copyWith(color: AppColors.onPrimary)),
              ),
              if (activePremium)
                FeedbackStatusBadge(
                  label: L10n.get(context, 'premiumV2ActivePremium'),
                  tone: BadgeTone.neutral,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Semantics(
            label: '${L10n.get(context, 'premiumV2CreditBalance')}: $credits',
            child: Text('$credits',
                style:
                    AppType.displayLarge.copyWith(color: AppColors.onPrimary)),
          ),
          const SizedBox(height: 2),
          Text(
            credits == 0
                ? L10n.get(context, 'premiumV2NoCredits')
                : L10n.get(context, 'premiumV2CreditHint'),
            style: AppType.caption
                .copyWith(color: AppColors.onPrimary.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}

/// Demo / Premium karşılaştırma kartı — yalnız gerçek desteklenen özellikler.
class PlanCompareCard extends StatelessWidget {
  const PlanCompareCard({
    super.key,
    required this.title,
    required this.priceLabel,
    required this.features,
    required this.highlighted,
    required this.icon,
    this.badge,
  });

  final String title;
  final String priceLabel;
  final List<String> features;
  final bool highlighted;
  final IconData icon;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final onGrad = highlighted;
    final titleColor = onGrad ? AppColors.onPrimary : AppColors.textPrimary;
    final featColor = onGrad
        ? AppColors.onPrimary.withValues(alpha: 0.92)
        : AppColors.textPrimary;
    return FeedbackCard(
      gradient: highlighted ? AppColors.primaryGradient : null,
      shadow: highlighted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  color: onGrad ? AppColors.onPrimary : AppColors.primary,
                  size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: AppType.cardTitle.copyWith(color: titleColor)),
              ),
              if (badge != null)
                FeedbackStatusBadge(label: badge!, tone: BadgeTone.neutral),
            ],
          ),
          const SizedBox(height: 4),
          Text(priceLabel,
              style: AppType.secondary.copyWith(
                  color: onGrad
                      ? AppColors.onPrimary.withValues(alpha: 0.9)
                      : AppColors.primary,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          for (final f in features)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 17,
                      color: onGrad ? AppColors.onPrimary : AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(f,
                          style: AppType.secondary.copyWith(color: featColor))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Satın alma kartı — store'dan gelen localized fiyat + gradient CTA.
class PurchaseCardV2 extends StatelessWidget {
  const PurchaseCardV2({
    super.key,
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
    return FeedbackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppType.cardTitle),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppType.secondary),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Text(price,
                  style:
                      AppType.sectionTitle.copyWith(color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          FeedbackPrimaryButton(
            label: '${L10n.get(context, 'iapBuy')} · $price',
            icon: Icons.lock_rounded,
            busy: busy,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}
