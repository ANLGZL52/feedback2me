import 'package:flutter/material.dart';

import 'feedback_colors.dart';

/// Feedback2Me V2 — tipografi ölçeği. Her metin bold değildir; net hiyerarşi.
/// Renk varsayılan olarak metin-birincil; ihtiyaç halinde `.copyWith(color:)`.
class AppType {
  AppType._();

  static const TextStyle displayLarge = TextStyle(
    fontSize: 32, fontWeight: FontWeight.w800, height: 1.15,
    letterSpacing: -0.5, color: AppColors.textPrimary);

  static const TextStyle display = TextStyle(
    fontSize: 28, fontWeight: FontWeight.w800, height: 1.2,
    letterSpacing: -0.4, color: AppColors.textPrimary);

  static const TextStyle pageTitle = TextStyle(
    fontSize: 24, fontWeight: FontWeight.w700, height: 1.25,
    letterSpacing: -0.3, color: AppColors.textPrimary);

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 18, fontWeight: FontWeight.w700, height: 1.3,
    color: AppColors.textPrimary);

  static const TextStyle cardTitle = TextStyle(
    fontSize: 17, fontWeight: FontWeight.w600, height: 1.3,
    color: AppColors.textPrimary);

  static const TextStyle body = TextStyle(
    fontSize: 15.5, fontWeight: FontWeight.w400, height: 1.45,
    color: AppColors.textPrimary);

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.4,
    color: AppColors.textPrimary);

  static const TextStyle secondary = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w400, height: 1.4,
    color: AppColors.textSecondary);

  static const TextStyle caption = TextStyle(
    fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.35,
    color: AppColors.textSecondary);

  static const TextStyle button = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w700, height: 1.1,
    letterSpacing: 0.2, color: AppColors.onPrimary);
}
