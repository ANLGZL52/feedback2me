import 'package:flutter/material.dart';

import '../feedback_colors.dart';
import '../feedback_radius.dart';
import '../feedback_spacing.dart';
import '../feedback_typography.dart';

/// Grouped settings bölümü — küçük başlık + yuvarlak yüzey + satırlar
/// (aralarında ince, girintili divider). Apple-benzeri temiz grouped list.
class FeedbackSettingsSection extends StatelessWidget {
  const FeedbackSettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(const Divider(
            height: 1, thickness: 1, color: AppColors.border, indent: 56));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.s),
          child: Text(title.toUpperCase(),
              style: AppType.caption
                  .copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w700)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.rLarge,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }
}

enum SettingsIconTone { primary, violet, neutral, danger, success }

/// Tek settings satırı — soft-zeminli ikon + başlık + alt metin + trailing.
class FeedbackSettingsTile extends StatelessWidget {
  const FeedbackSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.tone = SettingsIconTone.primary,
    this.danger = false,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final SettingsIconTone tone;
  final bool danger;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final effTone = danger ? SettingsIconTone.danger : tone;
    final iconBg = switch (effTone) {
      SettingsIconTone.primary => AppColors.primarySoft,
      SettingsIconTone.violet => AppColors.violetSoft,
      SettingsIconTone.neutral => AppColors.surfaceSecondary,
      SettingsIconTone.danger => AppColors.dangerSoft,
      SettingsIconTone.success => AppColors.successSoft,
    };
    final iconColor = switch (effTone) {
      SettingsIconTone.primary => AppColors.primary,
      SettingsIconTone.violet => AppColors.violet,
      SettingsIconTone.neutral => AppColors.textSecondary,
      SettingsIconTone.danger => AppColors.danger,
      SettingsIconTone.success => AppColors.success,
    };
    final titleColor = danger ? AppColors.danger : AppColors.textPrimary;

    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: iconBg, borderRadius: AppRadius.rSmall),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style:
                              AppType.bodyStrong.copyWith(color: titleColor)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: AppType.caption),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
