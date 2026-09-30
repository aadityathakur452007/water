// F5 — App-wide theme from the approved visual spec (Mode-1 restraint).
//
// Locked palette: white #FFFFFF ground, ink/primary black #111111 (same as
// the ErrorInfo black button), water blue #0284C7 for links/active/water
// cues ONLY. No gradients, no purple, hairline borders, radius 8, 48dp
// minimum targets. Component library stays Material (zero new deps; the
// shadcn_flutter dep in pubspec is unused by v1 screens — tokens mirror the
// same flat language so a later swap is config-only).

import 'package:flutter/material.dart';

/// Design tokens (single source for every new screen; feature-local token
/// classes from F2–F4 mirror these values and consolidate in F1's l10n pass).
abstract final class ShodashaTheme {
  /// Page + card ground (white, never grey panels).
  static const Color bg = Color(0xFFFFFFFF);

  /// Text + primary buttons (black — the ErrorInfo button color).
  static const Color ink = Color(0xFF111111);

  /// Secondary text.
  static const Color muted = Color(0xFF595959);

  /// Links / active nav / water cues ONLY — never a filled surface.
  static const Color blue = Color(0xFF0284C7);

  /// Blue at 8% for chips/tints (no gradients).
  static const Color blueTint = Color(0xFFE6F3FA);

  /// Hairline borders.
  static const Color border = Color(0xFFE5E5E5);

  /// Errors (spec: red text/icon, never color-alone — always + icon).
  static const Color danger = Color(0xFFB91C1C);

  /// Success cues (delivered / paid states).
  static const Color success = Color(0xFF15803D);

  static const double radius = 8;
  static const double minTarget = 48;

  /// Input + card + button shape.
  static RoundedRectangleBorder get shape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      );
}

/// MaterialApp theme: flat white, black primaries, blue accents.
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
        backgroundColor: ShodashaTheme.ink, // black primaries (locked)
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
        foregroundColor: ShodashaTheme.blue, // blue = links only
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
