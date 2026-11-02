import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
}

abstract final class ShodashaTheme {
  static const Color bg = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF0F172A);
  static const Color muted = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
  static const Color skeleton = Color(0xFFE2E8F0);

  static const Color teal = Color(0xFF0D9488);
  static const Color tealDark = Color(0xFF0F766E);
  static const Color tealDeep = Color(0xFF115E59);
  static const Color tealTint = Color(0xFFCCFBF1);

  static const Color success = Color(0xFF10B981);
  static const Color successDark = Color(0xFF047857);
  static const Color successTint = Color(0xFFD1FAE5);

  static const Color danger = Color(0xFFEF4444);
  static const Color dangerDark = Color(0xFFB91C1C);
  static const Color dangerTint = Color(0xFFFEE2E2);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningDark = Color(0xFFB45309);
  static const Color warningTint = Color(0xFFFEF3C7);

  static const double radius = 12.0;
  static const double radiusSm = 8.0;
  static const double radiusLg = 16.0;

  static const BoxShadow subtleCardShadow = BoxShadow(
    color: Color(0x0F0F172A),
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.light(
        primary: teal,
        onPrimary: Colors.white,
        surface: surface,
        onSurface: ink,
        error: danger,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
      ),
      fontFamily: 'Roboto',
    );
  }
}
