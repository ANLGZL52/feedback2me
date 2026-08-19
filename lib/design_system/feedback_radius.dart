import 'package:flutter/material.dart';

/// Feedback2Me V2 — köşe yarıçapları.
class AppRadius {
  AppRadius._();

  static const double small = 10;
  static const double medium = 14;
  static const double large = 18;
  static const double card = 22;
  static const double pill = 999;

  static BorderRadius get rSmall => BorderRadius.circular(small);
  static BorderRadius get rMedium => BorderRadius.circular(medium);
  static BorderRadius get rLarge => BorderRadius.circular(large);
  static BorderRadius get rCard => BorderRadius.circular(card);
  static BorderRadius get rPill => BorderRadius.circular(pill);
}
