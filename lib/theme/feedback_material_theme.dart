import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Apple HIG / Material 3 ile uyumlu koyu tema.
/// iOS’ta [fontFamily] verilmez → SF Pro; Android’de Roboto.
ThemeData buildFeedbackTheme() {
  final isCupertinoLike =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );

  final text = base.textTheme;
  // HIG’ye yakın okunabilirlik: gövde ~17pt, başlıklar net ağırlık farkı
  final textTheme = text.copyWith(
    titleLarge: text.titleLarge?.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: isCupertinoLike ? -0.4 : -0.2,
    ),
    titleMedium: text.titleMedium?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: isCupertinoLike ? -0.3 : 0,
    ),
    bodyLarge: text.bodyLarge?.copyWith(
      fontSize: 17,
      height: 1.35,
      fontWeight: FontWeight.w400,
    ),
    bodyMedium: text.bodyMedium?.copyWith(
      fontSize: 15,
      height: 1.4,
      color: Colors.white.withValues(alpha: 0.88),
    ),
    bodySmall: text.bodySmall?.copyWith(
      fontSize: 13,
      height: 1.35,
      color: Colors.white70,
    ),
    labelSmall: text.labelSmall?.copyWith(
      fontSize: 12,
      height: 1.3,
      letterSpacing: 0.1,
    ),
  );

  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppTheme.gold,
      brightness: Brightness.dark,
      primary: AppTheme.gold,
      surface: AppTheme.cardBg,
    ),
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: isCupertinoLike ? null : 'Roboto',
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppTheme.appBarBg,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: isCupertinoLike,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      toolbarHeight: isCupertinoLike ? 44 : kToolbarHeight,
    ),
    cardTheme: CardThemeData(
      color: AppTheme.cardBg,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isCupertinoLike ? 16 : 20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.gold,
        foregroundColor: const Color(0xFF1a1a1a),
        minimumSize: const Size(44, 48),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isCupertinoLike ? 14 : 16),
        ),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 48),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isCupertinoLike ? 14 : 16),
        ),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppTheme.navBarBg,
      selectedItemColor: AppTheme.gold,
      unselectedItemColor: Colors.white54,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w400,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      showDuration: const Duration(seconds: 4),
      textStyle: const TextStyle(fontSize: 13, color: Colors.white),
      decoration: BoxDecoration(
        color: const Color(0xE6323238),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    useMaterial3: true,
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

bool get feedbackAppUsesIosTypography =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
