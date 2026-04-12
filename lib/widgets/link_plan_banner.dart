import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/feedback_link.dart';
import 'link_validity_countdown.dart';

/// Demo / Premium / eski link — oluşturma sonrası ve listede belirgin gösterim.
class LinkPlanBanner extends StatelessWidget {
  const LinkPlanBanner({
    super.key,
    required this.link,
    this.compact = false,
  });

  final FeedbackLink link;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final plan = link.displayPlan;
    final (Color fg, Color border) = switch (plan) {
      FeedbackLinkPlan.demo => (
          const Color(0xFFFDBA74),
          const Color(0xFFEA580C),
        ),
      FeedbackLinkPlan.premium => (
          const Color(0xFFFDE68A),
          const Color(0xFFD4AF37),
        ),
      FeedbackLinkPlan.legacy => (
          Colors.white70,
          Colors.white24,
        ),
    };

    final title = switch (plan) {
      FeedbackLinkPlan.demo => L10n.get(context, 'linkPlanBannerDemo'),
      FeedbackLinkPlan.premium => L10n.get(context, 'linkPlanBannerPremium'),
      FeedbackLinkPlan.legacy => L10n.get(context, 'linkPlanBannerLegacy'),
    };

    final subtitle = switch (plan) {
      FeedbackLinkPlan.demo => L10n.get(context, 'linkPlanBannerDemoSub'),
      FeedbackLinkPlan.premium => L10n.get(context, 'linkPlanBannerPremiumSub'),
      FeedbackLinkPlan.legacy => L10n.get(context, 'linkPlanBannerLegacySub'),
    };

    final showCountdown = link.validUntil != null &&
        (link.isDemoTier || link.isPremiumTier);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 0 : 12,
        vertical: compact ? 2 : 10,
      ),
      decoration: compact
          ? null
          : BoxDecoration(
              color: fg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border.withValues(alpha: 0.65)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
          ),
          if (!compact) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: fg.withValues(alpha: 0.92),
                    height: 1.35,
                  ),
            ),
          ],
          if (showCountdown) ...[
            SizedBox(height: compact ? 4 : 8),
            LinkValidityCountdown(
              validUntil: link.validUntil!,
              compact: compact,
              foreground: fg.withValues(alpha: 0.95),
            ),
          ],
        ],
      ),
    );
  }
}
