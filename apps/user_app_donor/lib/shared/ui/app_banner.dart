import 'package:flutter/material.dart';

import '../../core/theme.dart';

enum AppBannerTone { offline, stale, success }

/// Inline state strip. Offline/5xx split stays with the caller; this widget
/// only owns the honest wording and the retry affordance.
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.tone,
    required this.title,
    this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  factory AppBanner.offline({
    Key? key,
    String? message,
    VoidCallback? onRetry,
  }) => AppBanner(
    key: key,
    tone: AppBannerTone.offline,
    title: "You're offline",
    message: message ?? 'Check your connection and try again.',
    onRetry: onRetry,
  );

  factory AppBanner.stale({Key? key, String? message, VoidCallback? onRetry}) =>
      AppBanner(
        key: key,
        tone: AppBannerTone.stale,
        title: 'Showing last update',
        message: message ?? 'Refresh to see the latest.',
        onRetry: onRetry,
        retryLabel: 'Refresh',
      );

  factory AppBanner.success({Key? key, String? message}) => AppBanner(
    key: key,
    tone: AppBannerTone.success,
    title: 'Back online',
    message: message ?? 'You are connected again.',
  );

  final AppBannerTone tone;
  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final (ground, ink, line, icon) = switch (tone) {
      AppBannerTone.offline => (
        ShodashaTheme.solarTint,
        ShodashaTheme.warning,
        ShodashaTheme.solarBorder,
        Icons.cloud_off,
      ),
      AppBannerTone.stale => (
        ShodashaTheme.tealTint,
        ShodashaTheme.tealDeep,
        ShodashaTheme.tealDark.withValues(alpha: 0.25),
        Icons.history,
      ),
      AppBannerTone.success => (
        ShodashaTheme.greenSoft,
        ShodashaTheme.successDark,
        ShodashaTheme.greenBorder,
        Icons.check_circle_outline,
      ),
    };

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: ground,
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
          border: Border.all(color: line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: ink),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      message!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: ink,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: ink,
                  minimumSize: const Size(
                    ShodashaTheme.minTarget,
                    ShodashaTheme.minTarget,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
                child: Text(retryLabel),
              ),
          ],
        ),
      ),
    );
  }
}
