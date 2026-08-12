import 'package:flutter/material.dart';

import '../feedback_colors.dart';
import '../feedback_radius.dart';
import '../feedback_typography.dart';

/// İstatistik kutusu — ikon + değer + etiket. Dashboard/profil metrikleri.
class FeedbackMetricCard extends StatelessWidget {
  const FeedbackMetricCard({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
    this.onSurface = false,
    this.loading = false,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color? iconColor;

  /// true: renkli/gradient kart üzerinde (beyaz metin).
  final bool onSurface;

  /// true: değer yerine küçük spinner (sonsuz "…" hissi vermez).
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final valColor = onSurface ? AppColors.onPrimary : AppColors.textPrimary;
    final labColor = onSurface
        ? AppColors.onPrimary.withValues(alpha: 0.8)
        : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: onSurface
            ? AppColors.onPrimary.withValues(alpha: 0.14)
            : AppColors.surfaceSecondary,
        borderRadius: AppRadius.rMedium,
      ),
      child: Column(
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: 18,
                color: iconColor ?? (onSurface ? valColor : AppColors.primary)),
            const SizedBox(height: 6),
          ],
          if (loading)
            SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: onSurface ? valColor : AppColors.primary),
            )
          else
            Text(value,
                style: AppType.sectionTitle.copyWith(color: valColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label,
              style: AppType.caption.copyWith(color: labColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
