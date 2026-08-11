import 'package:flutter/material.dart';

/// Feedback2Me V2 — aydınlık marka paleti.
/// TEK KAYNAK: ekranların içinde `Color(0x...)` yazma; buradan kullan.
class AppColors {
  AppColors._();

  // Zeminler / yüzeyler
  static const Color background = Color(0xFFF7F8FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSecondary = Color(0xFFF1F3FA);

  // Marka
  static const Color primary = Color(0xFF3557F6);
  static const Color primaryDark = Color(0xFF2846D8);
  static const Color violet = Color(0xFF7357F6);

  // Metin
  static const Color textPrimary = Color(0xFF111735);
  static const Color textSecondary = Color(0xFF68708C);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Çizgi / kenar
  static const Color border = Color(0xFFE7E9F2);

  // Durum renkleri
  static const Color success = Color(0xFF37C98B);
  static const Color warning = Color(0xFFF8B83E);
  static const Color danger = Color(0xFFEF5C63);

  // Ana gradient (mavi → mor)
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF3557F6), Color(0xFF7357F6)],
  );

  // Yumuşak mor/mavi hero zemin (splash / hero alanları)
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4C63F7), Color(0xFF7357F6)],
  );

  // Yardımcı tonlar (alpha ile üretilenler için hazır sabitler)
  static Color primarySoft = const Color(0xFF3557F6).withValues(alpha: 0.10);
  static Color violetSoft = const Color(0xFF7357F6).withValues(alpha: 0.10);
  static Color successSoft = const Color(0xFF37C98B).withValues(alpha: 0.12);
}
