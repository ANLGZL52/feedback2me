import 'package:flutter/material.dart';

import 'feedback_colors.dart';
import 'feedback_radius.dart';
import 'feedback_typography.dart';

/// Feedback2Me V2 — aydınlık ThemeData.
///
/// V2 ekranlar bunu `Theme(data: buildFeedbackLightTheme(), …)` ile sarabilir
/// ya da doğrudan design-system token'larını (AppColors/AppType…) kullanır.
/// Tüm uygulama V2'ye geçince global tema bu olacak; şimdilik V2 ekranlar
/// kendi içinde aydınlık, yeniden tasarlanmayanlar mevcut koyu temada kalır.
ThemeData buildFeedbackLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    error: AppColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    textTheme: const TextTheme(
      displaySmall: AppType.display,
      titleLarge: AppType.pageTitle,
      titleMedium: AppType.sectionTitle,
      bodyLarge: AppType.body,
      bodyMedium: AppType.secondary,
      labelSmall: AppType.caption,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: AppType.sectionTitle,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.rCard),
    ),
    dividerColor: AppColors.border,
    iconTheme: const IconThemeData(color: AppColors.textSecondary),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceSecondary,
      border: OutlineInputBorder(
          borderRadius: AppRadius.rMedium, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMedium, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.rMedium,
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      hintStyle: AppType.secondary,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
