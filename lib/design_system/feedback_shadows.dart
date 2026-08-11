import 'package:flutter/material.dart';

import 'feedback_colors.dart';

/// Feedback2Me V2 — aydınlık tema için çok yumuşak gölgeler.
/// Kalın border yerine gölge + zemin ile ayrım.
class AppShadows {
  AppShadows._();

  static List<BoxShadow> get card => [
        BoxShadow(
          color: const Color(0xFF111735).withValues(alpha: 0.06),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get soft => [
        BoxShadow(
          color: const Color(0xFF111735).withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get primaryGlow => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.28),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ];
}
