import 'package:flutter/material.dart';

import '../feedback_colors.dart';
import '../feedback_radius.dart';
import '../feedback_typography.dart';

/// "Nasıl çalışır?" numaralı adım (yatay/dikey listelerde).
class FeedbackStepItem extends StatelessWidget {
  const FeedbackStepItem({
    super.key,
    required this.number,
    required this.label,
    this.icon,
  });

  final int number;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: AppRadius.rMedium,
          ),
          child: icon != null
              ? Icon(icon, color: AppColors.primary, size: 20)
              : Text('$number',
                  style: AppType.cardTitle.copyWith(color: AppColors.primary)),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: AppType.caption, textAlign: TextAlign.center, maxLines: 2),
      ],
    );
  }
}

/// Küçük güven göstergesi (Anonim · Hızlı · Güvenli).
class FeedbackTrustChip extends StatelessWidget {
  const FeedbackTrustChip({super.key, required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.success),
        const SizedBox(width: 5),
        Text(label, style: AppType.caption),
      ],
    );
  }
}

/// Marka başlığı — logo balonu + isim (üst bar).
class FeedbackBrandMark extends StatelessWidget {
  const FeedbackBrandMark({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: AppRadius.rSmall,
          ),
          child: const Icon(Icons.chat_bubble_rounded,
              color: AppColors.onPrimary, size: 18),
        ),
        if (!compact) ...[
          const SizedBox(width: 8),
          Text('Feedback2Me',
              style: AppType.cardTitle.copyWith(fontWeight: FontWeight.w800)),
        ],
      ],
    );
  }
}
