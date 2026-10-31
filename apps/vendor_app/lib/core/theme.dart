// Vendor app theme — mirrors user_app ShodashaTheme (spec §4, locked).
// LIGHT ONLY, ink #111111 primaries, blue #0284C7 links/active only,
// white canvas, hairline borders, 8dp radius, 48dp targets, Material only.

import 'package:flutter/material.dart';

abstract final class ShodashaTheme {
  static const Color bg = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF111111);
  static const Color muted = Color(0xFF595959);
  static const Color blue = Color(0xFF0284C7);
  static const Color blueTint = Color(0xFFE6F3FA);
  static const Color amberTint = Color(0xFFFEF3C7);
  static const Color warning = Color(0xFFD97706);
  static const Color border = Color(0xFFE5E5E5);
  static const Color danger = Color(0xFFB91C1C);
  static const Color success = Color(0xFF15803D);

  static const double radius = 8;
  static const double radiusSheet = 24;
  static const List<BoxShadow> subtleCardShadow = [
    BoxShadow(
      color: Color(0x0A000000), // subtle 4% alpha shadow
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const double minTarget = 48;

  static RoundedRectangleBorder get shape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      );
}

/// 4/8/12/16/24/32 spacing scale — one rhythm across every vendor screen.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Phone-first content cap; wider layouts center instead of stretching.
const double kMaxContentWidth = 560;

/// Motion durations with reduced-motion gate.
abstract final class AppMotion {
  /// Micro interactions (icon swaps, ripples).
  static const Duration fast = Duration(milliseconds: 120);
  /// Most transitions and reveals.
  static const Duration normal = Duration(milliseconds: 220);
  /// Sheets, page transitions.
  static const Duration slow = Duration(milliseconds: 350);
  /// Returns 0ms when the platform requests reduced motion.
  static Duration responsive(BuildContext ctx, Duration d) {
    final mq = MediaQuery.of(ctx);
    return mq.disableAnimations ? Duration.zero : d;
  }
}

ThemeData buildShodashaTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ShodashaTheme.ink,
    ).copyWith(
      // WHY: force the locked palette over seed-derived purples.
      primary: ShodashaTheme.ink,
      onPrimary: ShodashaTheme.bg,
      secondary: ShodashaTheme.blue,
      surface: ShodashaTheme.bg,
      onSurface: ShodashaTheme.ink,
      error: ShodashaTheme.danger,
    ),
    scaffoldBackgroundColor: ShodashaTheme.bg,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: ShodashaTheme.bg,
      foregroundColor: ShodashaTheme.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: ShodashaTheme.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ShodashaTheme.bg,
      indicatorColor: ShodashaTheme.blueTint,
      height: 64,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? ShodashaTheme.blue
                : ShodashaTheme.muted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            fontWeight:
                states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? ShodashaTheme.blue
                : ShodashaTheme.muted,
          )),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ShodashaTheme.ink,
        foregroundColor: ShodashaTheme.bg,
        disabledBackgroundColor: ShodashaTheme.ink.withValues(alpha: 0.3),
        minimumSize: const Size.fromHeight(ShodashaTheme.minTarget),
        shape: ShodashaTheme.shape,
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ShodashaTheme.ink,
        side: const BorderSide(color: ShodashaTheme.ink),
        minimumSize: const Size(ShodashaTheme.minTarget, ShodashaTheme.minTarget),
        shape: ShodashaTheme.shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ShodashaTheme.blue,
        minimumSize: const Size(ShodashaTheme.minTarget, ShodashaTheme.minTarget),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ShodashaTheme.bg,
      hintStyle: const TextStyle(color: ShodashaTheme.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.blue),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.danger),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: ShodashaTheme.ink,
      contentTextStyle: TextStyle(color: ShodashaTheme.bg),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: ShodashaTheme.border),
  );
}
