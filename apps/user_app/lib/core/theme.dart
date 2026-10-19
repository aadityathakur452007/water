// ONE theme file (v2 law — no screen defines its own tokens or ThemeData).
//
// 032-user-app-replacement: the donor visual language (Eco-Pure teal
// structure, solar-yellow highlights, emerald success) is the base. The
// money-safety laws stay locked and never yield to donor styling:
//   • green = money CTAs ONLY (BOOK NOW / Pay / Confirm)
//   • blue  = links / info text ONLY — never a filled surface
//   • teal  = brand structure, nav, active states
//   • slate page ground + white cards, 48dp targets, no gradients in v1.

import 'package:flutter/material.dart';

/// Design tokens (single source for every screen in this app).
abstract final class ShodashaTheme {
  // ── Ground & ink (slate family) ────────────────────────────────────────
  /// Page ground (slate-50; cards paint white on top of it).
  static const Color bg = Color(0xFFF8FAFC);

  /// Card / sheet ground (white on slate ground).
  static const Color surface = Color(0xFFFFFFFF);

  /// Text primary (slate-900).
  static const Color ink = Color(0xFF0F172A);

  /// Text secondary (slate-500).
  static const Color muted = Color(0xFF64748B);

  /// Hairline borders (slate-200).
  static const Color border = Color(0xFFE2E8F0);

  // ── Brand teal (nav / structure / active) ──────────────────────────────
  /// Brand teal (nav/structure/active).
  static const Color teal = Color(0xFF0D9488);

  /// Teal press/hover dark.
  static const Color tealDark = Color(0xFF0F766E);

  /// Deep teal for on-teal surfaces.
  static const Color tealDeep = Color(0xFF115E59);

  /// Teal 10% tint for chips/indicators (no gradients).
  static const Color tealTint = Color(0xFFCCFBF1);

  // ── Money green (CTAs only) ────────────────────────────────────────────
  /// Money CTA green — BOOK NOW / Pay / confirm buttons ONLY.
  static const Color green = Color(0xFF16A34A);

  /// Green press/hover dark (same money-only rule).
  static const Color greenDark = Color(0xFF15803D);

  /// Success banner ground.
  static const Color greenSoft = Color(0xFFF0FDF4);

  /// Success chip/tile tint.
  static const Color greenTint = Color(0xFFDCFCE7);

  /// Success tile border.
  static const Color greenBorder = Color(0xFFBBF7D0);

  // ── Solar accent (badges / highlights — never CTAs) ────────────────────
  /// Solar yellow — badges, highlights, streak marks. Never a money CTA.
  static const Color solar = Color(0xFFFACC15);

  /// Solar dark for icon/text on light grounds.
  static const Color solarDark = Color(0xFFCA8A04);

  /// Solar tint ground for slots/notes.
  static const Color solarTint = Color(0xFFFEF9C3);

  /// Solar tile border.
  static const Color solarBorder = Color(0xFFFDE047);

  /// Ink on solar fills (amber-900).
  static const Color onSolar = Color(0xFF78350F);

  // ── Info blue (links / ETA — never a filled surface) ───────────────────
  /// Links / deep body links ONLY — never a filled surface.
  static const Color blue = Color(0xFF0284C7);

  /// Blue at 8% for chips/tints.
  static const Color blueTint = Color(0xFFE6F3FA);

  /// ETA / info text (sky-700).
  static const Color eta = Color(0xFF0369A1);

  /// ETA chip tint (sky-100).
  static const Color etaTint = Color(0xFFE0F2FE);

  // ── Status ─────────────────────────────────────────────────────────────
  /// Errors (red text/icon, never color-alone — always + icon).
  static const Color danger = Color(0xFFB91C1C);

  /// Success cues (delivered / paid states) — emerald.
  static const Color success = Color(0xFF10B981);

  // ── Metrics ────────────────────────────────────────────────────────────
  /// Small radius (chips, tiles inside cards).
  static const double radiusSm = 8;

  /// Default card/button radius.
  static const double radius = 12;

  /// Large radius (hero cards, feature tiles).
  static const double radiusLg = 16;

  /// Bottom sheet top radius.
  static const double radiusSheet = 28;

  /// Minimum touch target (48dp, a11y law).
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
    cardTheme: CardThemeData(
      color: ShodashaTheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
        side: const BorderSide(color: ShodashaTheme.border),
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
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w500,
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
        minimumSize:
            const Size(ShodashaTheme.minTarget, ShodashaTheme.minTarget),
        shape: ShodashaTheme.shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ShodashaTheme.blue, // blue = links only
        minimumSize:
            const Size(ShodashaTheme.minTarget, ShodashaTheme.minTarget),
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
