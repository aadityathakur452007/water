// Donor token aliases — compatibility facade over ShodashaTheme.
//
// 035 WS1: there is ONE palette (`core/theme.dart`). These names stay so the
// imported donor screens keep compiling without a second colour system.
// `error` deliberately maps to the darker accessible danger token.
import 'package:flutter/material.dart';

import '../theme.dart';

class AppColors {
  static const Color primary = ShodashaTheme.teal;
  static const Color primaryDark = ShodashaTheme.tealDeep;
  static const Color accent = ShodashaTheme.solar;
  static const Color accentDark = ShodashaTheme.solarDark;
  static const Color accentHover = ShodashaTheme.solarHover;

  static const Color background = ShodashaTheme.bg;
  static const Color surface = ShodashaTheme.surface;
  static const Color cardBg = ShodashaTheme.surface;
  static const Color border = ShodashaTheme.border;
  static const Color divider = ShodashaTheme.border;

  static const Color textPrimary = ShodashaTheme.ink;
  static const Color textSecondary = ShodashaTheme.muted;
  static const Color textOnPrimary = ShodashaTheme.surface;
  static const Color textOnAccent = ShodashaTheme.onSolar;

  static const Color success = ShodashaTheme.success;
  static const Color successDark = ShodashaTheme.successDark;
  static const Color error = ShodashaTheme.danger;
  static const Color warning = ShodashaTheme.warning;
  static const Color link = ShodashaTheme.link;
  static const Color skeleton = ShodashaTheme.skeleton;

  /// Money CTA green (same locked token as core/theme.dart).
  static const Color money = ShodashaTheme.green;
}

class AppConstants {
  static const String appName = 'SHODASHA';
  static const double smallPadding = AppSpacing.sm;
  static const double defaultPadding = AppSpacing.lg;
  static const double largePadding = AppSpacing.xl;
  static const double cardBorderRadius = ShodashaTheme.radiusLg;
  static const double buttonBorderRadius = ShodashaTheme.radius;
  static const double minTapTarget = ShodashaTheme.minTarget;
  static const double iconSize = 24.0;
  static const double borderRadius = ShodashaTheme.radius;
  static const double sectionGap = AppSpacing.xl;
  static const double maxContentWidth = kMaxContentWidth;
}
