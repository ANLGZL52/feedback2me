import 'package:flutter/material.dart';

import '../feedback_colors.dart';
import '../feedback_typography.dart';

/// Kullanıcı avatarı — görsel yoksa baş harf + gradient.
class FeedbackAvatar extends StatelessWidget {
  const FeedbackAvatar({
    super.key,
    this.name,
    this.imageUrl,
    this.size = 44,
  });

  final String? name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final initial =
        (name != null && name!.trim().isNotEmpty) ? name!.trim()[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: AppType.cardTitle.copyWith(
          color: AppColors.onPrimary,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
