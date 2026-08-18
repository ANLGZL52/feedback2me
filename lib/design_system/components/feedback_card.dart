import 'package:flutter/material.dart';

import '../feedback_colors.dart';
import '../feedback_radius.dart';
import '../feedback_shadows.dart';
import '../feedback_typography.dart';

/// Temel V2 kart — beyaz yüzey + yumuşak gölge + geniş radius.
class FeedbackCard extends StatelessWidget {
  const FeedbackCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color,
    this.gradient,
    this.border = true,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final bool border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? AppColors.surface) : null,
        gradient: gradient,
        borderRadius: AppRadius.rCard,
        border: border && gradient == null
            ? Border.all(color: AppColors.border)
            : null,
        boxShadow: shadow ? AppShadows.card : null,
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.rCard,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// Aksiyon/özellik kartı — ikon + başlık + açıklama + ok göstergesi (ana ekran).
class FeedbackFeatureCard extends StatelessWidget {
  const FeedbackFeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.iconGradient,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final Gradient? iconGradient;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return FeedbackCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: iconGradient ?? AppColors.primaryGradient,
              borderRadius: AppRadius.rMedium,
            ),
            child: Icon(icon, color: AppColors.onPrimary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.cardTitle),
                const SizedBox(height: 3),
                Text(description, style: AppType.secondary),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surfaceSecondary,
              borderRadius: AppRadius.rSmall,
            ),
            child: const Icon(Icons.arrow_forward_rounded,
                color: AppColors.primary, size: 18),
          ),
        ],
      ),
    );
  }
}
