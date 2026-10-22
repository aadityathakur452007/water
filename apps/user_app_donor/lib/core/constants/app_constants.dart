// Donor visual tokens. These are the exact palette/spacing values from the
// donor app (76e0eba), kept in one place so the imported screens do not each
// invent colors. Money CTAs remain the shared green from core/theme.dart.
import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF0D9488);
  static const Color primaryDark = Color(0xFF115E59);
  static const Color accent = Color(0xFFFACC15);
  static const Color accentDark = Color(0xFFCA8A04);
  static const Color accentHover = Color(0xFFEAB308);

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFE2E8F0);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textOnPrimary = Colors.white;
  static const Color textOnAccent = Color(0xFF78350F);

  static const Color success = Color(0xFF10B981);
  static const Color error = Color(0xFFEF4444);

  /// Money CTA green (same locked token as core/theme.dart).
  static const Color money = Color(0xFF16A34A);
}

class AppConstants {
  static const String appName = 'SHODASHA';
  static const double smallPadding = 8.0;
  static const double defaultPadding = 16.0;
  static const double largePadding = 24.0;
  static const double cardBorderRadius = 16.0;
  static const double buttonBorderRadius = 10.0;
  static const double minTapTarget = 48.0;
  static const double iconSize = 24.0;
  static const double borderRadius = 12.0;
}
