import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../l10n/app_localizations.dart';
import '../../models/user_profile.dart';

/// V2 profil başlığı — avatar + isim + ikincil kimlik + hesap rozetleri.
/// Yalnızca gerçek [UserProfile] alanlarını gösterir; sahte alan üretmez.
class FeedbackProfileHeader extends StatelessWidget {
  const FeedbackProfileHeader({super.key, required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final displayName = profile?.displayName?.trim();
    final name = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : L10n.get(context, 'profileDefaultUser');
    final email = profile?.email?.trim();
    final handle = profile?.handle?.trim();
    final secondary = (email != null && email.isNotEmpty)
        ? email
        : ((handle != null && handle.isNotEmpty) ? handle : null);
    final credits = profile?.paidLinkCredits ?? 0;
    final premium = profile?.hasActivePremium ?? false;

    return Column(
      children: [
        FeedbackAvatar(name: name, imageUrl: profile?.photoUrl, size: 76),
        const SizedBox(height: AppSpacing.m),
        Text(name, style: AppType.pageTitle, textAlign: TextAlign.center),
        if (secondary != null) ...[
          const SizedBox(height: 4),
          Text(secondary,
              style: AppType.secondary, textAlign: TextAlign.center),
        ],
        if (premium || credits > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              if (premium)
                FeedbackStatusBadge(
                    label: L10n.get(context, 'tierPremium'),
                    tone: BadgeTone.primary),
              if (credits > 0)
                FeedbackStatusBadge(
                  label: L10n.get(context, 'profileV2Credits')
                      .replaceFirst('{n}', '$credits'),
                  tone: BadgeTone.success,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
