// F5 → 031 palette v2 (031-user-app-ui-revamp): premium direction adopted
// from the friend's design audit (Feature_docs/user-app-ui-import-audit/).
// Locked by owner 2026-10-17: teal brand #0D9488 (nav/structure/active),
// green CTA #16A34A (money buttons only), slate-50 page ground with WHITE
// cards, blue stays link-only. No gradients inside v1 screens; radius lifts
// 8→12; 48dp targets untouched. Component library stays Material (zero deps).

import 'package:flutter/material.dart';

/// Design tokens (single source for every new screen; feature-local token
/// classes from F2–F4 mirror these values and consolidate in F1's l10n pass).
abstract final class ShodashaTheme {
  /// Page ground (slate-50; cards paint white on top of it).
  static const Color bg = Color(0xFFF8FAFC);

  /// Card / sheet ground (white on slate ground).
  static const Color surface = Color(0xFFFFFFFF);

  /// Text primary (slate-900).
  static const Color ink = Color(0xFF0F172A);

  /// Text secondary (slate-500).
  static const Color muted = Color(0xFF64748B);

  /// Brand teal — nav, active states, structure, chips, focus. Never money.
  static const Color teal = Color(0xFF0D9488);

  /// Teal 10% tint for chips/indicators (no gradients).
  static const Color tealTint = Color(0xFFCCFBF1);

  /// Money CTA green — BOOK NOW / Pay / confirm buttons ONLY.
  static const Color green = Color(0xFF16A34A);

  /// Links / deep body links ONLY — never a filled surface (v1 rule kept).
  static const Color blue = Color(0xFF0284C7);

  /// Blue at 8% for chips/tints (unchanged from v1).
  static const Color blueTint = Color(0xFFE6F3FA);

  /// Hairline borders (slate-200).
  static const Color border = Color(0xFFE2E8F0);

  /// Errors (spec: red text/icon, never color-alone — always + icon).
  static const Color danger = Color(0xFFB91C1C);

  /// Success cues (delivered / paid states) — emerald.
  static const Color success = Color(0xFF10B981);

  static const double radius = 12;
  static const double minTarget = 48;

  /// Input + card + button shape.
  static RoundedRectangleBorder get shape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      );
}

/// MaterialApp theme: slate ground, teal brand, green money CTA, blue links.
ThemeData buildShodashaTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ShodashaTheme.teal,
    ).copyWith(
      // WHY: force the locked palette over seed-derived drift.
      primary: ShodashaTheme.teal,
      onPrimary: ShodashaTheme.surface,
      secondary: ShodashaTheme.green,
      surface: ShodashaTheme.surface,
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
        fontWeight: FontWeight.w800,
        color: ShodashaTheme.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ShodashaTheme.surface,
      indicatorColor: ShodashaTheme.tealTint,
      height: 64,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? ShodashaTheme.teal
                : ShodashaTheme.muted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            fontWeight:
                states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? ShodashaTheme.teal
                : ShodashaTheme.muted,
          )),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ShodashaTheme.green, // money CTA (locked)
        foregroundColor: ShodashaTheme.surface,
        disabledBackgroundColor: ShodashaTheme.green.withValues(alpha: 0.3),
        minimumSize: const Size.fromHeight(ShodashaTheme.minTarget),
        shape: ShodashaTheme.shape,
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ShodashaTheme.teal,
        side: const BorderSide(color: ShodashaTheme.teal),
        minimumSize: const Size(ShodashaTheme.minTarget, ShodashaTheme.minTarget),
        shape: ShodashaTheme.shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ShodashaTheme.blue, // blue = links only
        minimumSize: const Size(ShodashaTheme.minTarget, ShodashaTheme.minTarget),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ShodashaTheme.surface,
      hintStyle: const TextStyle(color: ShodashaTheme.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.teal),
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
