import 'package:flutter/material.dart';

import '../feedback_colors.dart';
import '../feedback_radius.dart';
import '../feedback_typography.dart';

/// TR / EN geçişi (kontrollü). Dil ayarlama mantığı çağıran ekrandadır;
/// bu bileşen yalnızca mevcut seçimi gösterir ve seçim geri çağrısı verir.
class FeedbackLanguageSelector extends StatelessWidget {
  const FeedbackLanguageSelector({
    super.key,
    required this.currentCode,
    required this.onSelect,
  });

  /// 'tr' | 'en'
  final String currentCode;
  final void Function(String code) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: AppRadius.rPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg('TR', 'tr'),
          _seg('EN', 'en'),
        ],
      ),
    );
  }

  Widget _seg(String label, String code) {
    final selected = currentCode == code;
    return GestureDetector(
      onTap: () => onSelect(code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: AppRadius.rPill,
        ),
        child: Text(
          label,
          style: AppType.caption.copyWith(
            color: selected ? AppColors.onPrimary : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
