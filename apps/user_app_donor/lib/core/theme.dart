// ONE theme file (v2 law — no screen defines its own tokens or ThemeData).
//
// 032-user-app-replacement: the donor visual language (Eco-Pure teal
// structure, solar-yellow highlights, emerald success) is the base. The
// money-safety laws stay locked and never yield to donor styling:
//   • green = money CTAs ONLY (BOOK NOW / Pay / Confirm)
//   • blue  = links / info text ONLY — never a filled surface
//   • teal  = brand structure, nav, active states
//   • slate page ground + white cards, 48dp targets, no gradients in v1.
//
// 035 WS1: one token source for every screen. New semantic tokens
// (successDark / warning / link / skeleton), a platform-default type scale,
// the 4/8/12/16/24/32 spacing scale, and reduced-motion-aware durations.

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

  /// Text secondary (slate-500) — AA on white.
  static const Color muted = Color(0xFF64748B);

  /// Hairline borders (slate-200).
  static const Color border = Color(0xFFE2E8F0);

  /// Skeleton blocks while a real read is in flight (slate-200).
  static const Color skeleton = Color(0xFFE2E8F0);

  // ── Brand teal (nav / structure / active) ──────────────────────────────
  /// Brand teal (nav/structure/active).
  static const Color teal = Color(0xFF0D9488);

  /// Teal press/hover dark.
  static const Color tealDark = Color(0xFF0F766E);

  /// Deep teal for white-on-teal surfaces (AA with white text).
  static const Color tealDeep = Color(0xFF115E59);

  /// Teal 10% tint for chips/indicators (no gradients).
  static const Color tealTint = Color(0xFFCCFBF1);

  // ── Money green (CTAs only) ────────────────────────────────────────────
  /// Money CTA green — BOOK NOW / Pay / confirm buttons ONLY.
  static const Color green = Color(0xFF16A34A);

  /// Money CTA fill where a white label is needed (AA with white text).
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

  /// Solar hover/pressed accent.
  static const Color solarHover = Color(0xFFEAB308);

  /// Solar dark for icon/text on light grounds.
  static const Color solarDark = Color(0xFFCA8A04);

  /// Solar tint ground for slots/notes.
  static const Color solarTint = Color(0xFFFEF9C3);

  /// Solar tile border.
  static const Color solarBorder = Color(0xFFFDE047);

  /// Ink on solar fills (amber-900).
  static const Color onSolar = Color(0xFF78350F);

  // ── Info blue (links / ETA — never a filled surface) ───────────────────
  /// Links / info icons — never a filled surface.
  static const Color blue = Color(0xFF0284C7);

  /// Blue at 8% for chips/tints.
  static const Color blueTint = Color(0xFFE6F3FA);

  /// Link text on white (sky-700; AA).
  static const Color link = Color(0xFF0369A1);

  /// ETA / info text (same accessible sky as links).
  static const Color eta = link;

  /// ETA chip tint (sky-100).
  static const Color etaTint = Color(0xFFE0F2FE);

  // ── Status ─────────────────────────────────────────────────────────────
  /// Errors (red text/icon, never color-alone — always + icon).
  static const Color danger = Color(0xFFB91C1C);

  /// Success cues (delivered / paid states) — emerald fill.
  static const Color success = Color(0xFF10B981);

  /// Success text/icons on light grounds (AA on white).
  static const Color successDark = Color(0xFF047857);

  /// Warning text/icons (amber-700; AA on white).
  static const Color warning = Color(0xFFB45309);

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
  static RoundedRectangleBorder get shape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
}

/// 4/8/12/16/24/32 spacing scale (one rhythm across every screen).
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

/// Motion durations and the one reduced-motion gate.
abstract final class AppMotion {
  /// Press / micro feedback (150ms).
  static const Duration fast = Duration(milliseconds: 150);

  /// Sheet / state transition (180ms).
  static const Duration normal = Duration(milliseconds: 180);

  /// Larger state change (220ms).
  static const Duration slow = Duration(milliseconds: 220);

  /// True when the platform asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// Zero when reduced motion is on, otherwise [duration].
  static Duration resolve(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// System typeface only — no font asset, no extra download.
TextTheme _shodashaTextTheme(TextTheme base) => base.copyWith(
  displaySmall: const TextStyle(
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    color: ShodashaTheme.ink,
  ),
  headlineSmall: const TextStyle(
    fontSize: 22,
    height: 1.25,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: ShodashaTheme.ink,
  ),
  titleLarge: const TextStyle(
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: ShodashaTheme.ink,
  ),
  titleMedium: const TextStyle(
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w700,
    color: ShodashaTheme.ink,
  ),
  titleSmall: const TextStyle(
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: ShodashaTheme.ink,
  ),
  bodyLarge: const TextStyle(
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w500,
    color: ShodashaTheme.ink,
  ),
  bodyMedium: const TextStyle(
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w500,
    color: ShodashaTheme.ink,
  ),
  bodySmall: const TextStyle(
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w500,
    color: ShodashaTheme.muted,
  ),
  labelLarge: const TextStyle(
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: ShodashaTheme.ink,
  ),
  labelMedium: const TextStyle(
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: ShodashaTheme.muted,
  ),
  labelSmall: const TextStyle(
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: ShodashaTheme.muted,
  ),
);

/// MaterialApp theme: slate ground, teal brand, green money CTA, blue links.
ThemeData buildShodashaTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: ShodashaTheme.teal).copyWith(
      // WHY: force the locked palette over seed-derived drift.
      primary: ShodashaTheme.teal,
      onPrimary: ShodashaTheme.surface,
      secondary: ShodashaTheme.green,
      onSecondary: ShodashaTheme.surface,
      surface: ShodashaTheme.surface,
      onSurface: ShodashaTheme.ink,
      error: ShodashaTheme.danger,
      onError: ShodashaTheme.surface,
    ),
    scaffoldBackgroundColor: ShodashaTheme.bg,
  );
  return base.copyWith(
    textTheme: _shodashaTextTheme(base.textTheme),
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
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? ShodashaTheme.tealDeep
              : ShodashaTheme.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? ShodashaTheme.tealDeep
              : ShodashaTheme.muted,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style:
          ElevatedButton.styleFrom(
            backgroundColor: ShodashaTheme.greenDark, // money CTA (locked)
            foregroundColor: ShodashaTheme.surface,
            disabledBackgroundColor: ShodashaTheme.border,
            disabledForegroundColor: ShodashaTheme.muted,
            elevation: 0,
            minimumSize: const Size.fromHeight(ShodashaTheme.minTarget),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.pressed)
                  ? ShodashaTheme.surface.withValues(alpha: 0.14)
                  : null,
            ),
          ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ShodashaTheme.tealDeep,
        foregroundColor: ShodashaTheme.surface,
        disabledBackgroundColor: ShodashaTheme.border,
        disabledForegroundColor: ShodashaTheme.muted,
        elevation: 0,
        minimumSize: const Size(0, ShodashaTheme.minTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ShodashaTheme.tealDeep,
        side: const BorderSide(color: ShodashaTheme.tealDark),
        minimumSize: const Size(
          ShodashaTheme.minTarget,
          ShodashaTheme.minTarget,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ShodashaTheme.link,
        minimumSize: const Size(
          ShodashaTheme.minTarget,
          ShodashaTheme.minTarget,
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ShodashaTheme.surface,
      constraints: const BoxConstraints(minHeight: ShodashaTheme.minTarget),
      hintStyle: const TextStyle(color: ShodashaTheme.muted),
      labelStyle: const TextStyle(
        color: ShodashaTheme.muted,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: const TextStyle(
        color: ShodashaTheme.tealDeep,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      helperStyle: const TextStyle(color: ShodashaTheme.muted, fontSize: 12),
      errorStyle: const TextStyle(
        color: ShodashaTheme.danger,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      counterStyle: const TextStyle(color: ShodashaTheme.muted, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.tealDark, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.danger, width: 2),
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
