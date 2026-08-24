import 'package:flutter/material.dart';

import '../feedback_colors.dart';
import '../feedback_radius.dart';
import '../feedback_typography.dart';

enum BadgeTone { primary, success, warning, danger, neutral }

/// Durum rozeti (pill). Aktif/Demo/Premium vb.
class FeedbackStatusBadge extends StatelessWidget {
  const FeedbackStatusBadge({
    super.key,
    required this.label,
    this.tone = BadgeTone.primary,
    this.dot = false,
    this.icon,
    this.onGradient = false,
  });

  final String label;
  final BadgeTone tone;
  final bool dot;
  final IconData? icon;

  /// Koyu/gradient bir kart üzerinde gösterildiğinde beyaz, yüksek-kontrast
  /// stil kullanır (aksi halde `neutral` gibi gri tonlar okunmaz kalır).
  final bool onGradient;

  Color get _color {
    switch (tone) {
      case BadgeTone.success:
        return AppColors.success;
      case BadgeTone.warning:
        return AppColors.warning;
      case BadgeTone.danger:
        return AppColors.danger;
      case BadgeTone.neutral:
        return AppColors.textSecondary;
      case BadgeTone.primary:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Gradient üzerinde: beyaz metin + yarı saydam beyaz zemin (yüksek kontrast).
    final c = onGradient ? AppColors.onPrimary : _color;
    final bg = onGradient
        ? AppColors.onPrimary.withValues(alpha: 0.22)
        : c.withValues(alpha: 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.rPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: AppType.caption
                  .copyWith(color: c, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
