import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../l10n/app_localizations.dart';
import '../../models/feedback_link.dart';
import '../link_validity_countdown.dart';

/// V2 link geçmişi kartı — durum + tarih/geri sayım + tier + kısa URL +
/// feedback sayısı + aksiyonlar. Yalnızca gerçek [FeedbackLink] alanlarından
/// türetilir; yeni status/alan üretilmez. İş mantığı callback'lerle gelir.
class LinkHistoryCard extends StatelessWidget {
  const LinkHistoryCard({
    super.key,
    required this.link,
    required this.feedbackCount,
    required this.onShare,
    required this.onCopy,
    required this.onSummary,
    required this.onComments,
    this.onTap,
  });

  final FeedbackLink link;

  /// null → sayım yükleniyor.
  final int? feedbackCount;
  final VoidCallback onShare;
  final VoidCallback onCopy;
  final VoidCallback onSummary;
  final VoidCallback onComments;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = link.acceptsPublicFeedback;
    final demo = link.isDemoTier;
    final tierLabel =
        demo ? L10n.get(context, 'tierDemo') : L10n.get(context, 'tierPremium');
    final count = feedbackCount;
    final countText = count == null
        ? '…'
        : L10n.get(context, 'commentsCount').replaceFirst('{n}', '$count');

    return FeedbackCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FeedbackStatusBadge(
                label: active
                    ? L10n.get(context, 'profileV2Active')
                    : L10n.get(context, 'profileV2Completed'),
                tone: active ? BadgeTone.success : BadgeTone.neutral,
                dot: active,
              ),
              const Spacer(),
              if (active && link.validUntil != null)
                LinkValidityCountdown(
                    validUntil: link.validUntil!,
                    compact: true,
                    foreground: AppColors.primary)
              else if (link.createdAt != null)
                Text(
                    MaterialLocalizations.of(context)
                        .formatShortDate(link.createdAt!),
                    style: AppType.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(demo ? Icons.science_rounded : Icons.workspace_premium_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(tierLabel, style: AppType.cardTitle),
            ],
          ),
          const SizedBox(height: 4),
          Text(link.shareUrl,
              style: AppType.secondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.forum_rounded,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(countText, style: AppType.secondary),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          if (active)
            Row(
              children: [
                Expanded(
                  child: FeedbackPrimaryButton(
                    label: L10n.get(context, 'shareLink'),
                    icon: Icons.ios_share_rounded,
                    onPressed: onShare,
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: FeedbackSecondaryButton(
                    label: L10n.get(context, 'copyLink'),
                    icon: Icons.copy_rounded,
                    onPressed: onCopy,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: FeedbackPrimaryButton(
                    label: L10n.get(context, 'profileV2ViewSummary'),
                    icon: Icons.insights_rounded,
                    onPressed: onSummary,
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: FeedbackSecondaryButton(
                    label: L10n.get(context, 'profileV2ViewComments'),
                    icon: Icons.forum_rounded,
                    onPressed: onComments,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
