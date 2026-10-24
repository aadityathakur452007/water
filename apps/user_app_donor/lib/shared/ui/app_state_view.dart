import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'app_button.dart';

enum _StateKind { loading, empty, error, stale, content }

/// One state grammar for async surfaces: skeleton, empty, error, stale,
/// content. No raw HTTP status codes cross this boundary.
class AppStateView extends StatelessWidget {
  const AppStateView._(
    this._kind, {
    super.key,
    this.title,
    this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.skeletonLines = 3,
    this.isNetwork = false,
    this.child,
  });

  factory AppStateView.loading({Key? key, int lines = 3, String? message}) =>
      AppStateView._(
        _StateKind.loading,
        key: key,
        message: message,
        skeletonLines: lines,
      );

  factory AppStateView.empty({
    Key? key,
    required String title,
    String? message,
    IconData icon = Icons.inbox_outlined,
    String? actionLabel,
    VoidCallback? onAction,
  }) => AppStateView._(
    _StateKind.empty,
    key: key,
    title: title,
    message: message,
    icon: icon,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  factory AppStateView.error({
    Key? key,
    bool isNetwork = false,
    String? title,
    String? message,
    String? actionLabel,
    VoidCallback? onRetry,
    IconData? icon,
  }) => AppStateView._(
    _StateKind.error,
    key: key,
    title: title ?? (isNetwork ? "You're offline" : 'Server problem'),
    message:
        message ??
        (isNetwork
            ? 'Check your connection and try again.'
            : "We couldn't load this right now. Try again in a moment."),
    icon: icon ?? (isNetwork ? Icons.cloud_off : Icons.error_outline),
    actionLabel: actionLabel ?? 'Retry',
    onAction: onRetry,
    isNetwork: isNetwork,
  );

  factory AppStateView.stale({
    Key? key,
    String? title,
    String? message,
    String? actionLabel,
    VoidCallback? onRetry,
  }) => AppStateView._(
    _StateKind.stale,
    key: key,
    title: title ?? 'Showing last update',
    message: message ?? 'Refresh to see the latest.',
    icon: Icons.history,
    actionLabel: actionLabel ?? 'Refresh',
    onAction: onRetry,
  );

  factory AppStateView.content({Key? key, required Widget child}) =>
      AppStateView._(_StateKind.content, key: key, child: child);

  final _StateKind _kind;
  final String? title;
  final String? message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final int skeletonLines;
  final bool isNetwork;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (_kind == _StateKind.content) return child ?? const SizedBox.shrink();
    if (_kind == _StateKind.loading) {
      return Semantics(
        container: true,
        label: message ?? 'Loading',
        child: ExcludeSemantics(
          child: Padding(
            key: const Key('app-state-loading'),
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SkeletonBlock(width: 148, height: 14),
                const SizedBox(height: AppSpacing.md),
                const _SkeletonBlock(width: double.infinity, height: 72),
                const SizedBox(height: AppSpacing.md),
                for (var i = 0; i < skeletonLines; i++) ...[
                  _SkeletonBlock(
                    width: i.isEven ? double.infinity : 220,
                    height: 12,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final tint = switch (_kind) {
      _StateKind.empty => ShodashaTheme.tealTint,
      _StateKind.stale => ShodashaTheme.solarTint,
      _StateKind.error =>
        isNetwork
            ? ShodashaTheme.solarTint
            : ShodashaTheme.danger.withValues(alpha: 0.08),
      _StateKind.loading || _StateKind.content => ShodashaTheme.tealTint,
    };
    final tone = switch (_kind) {
      _StateKind.empty => ShodashaTheme.tealDeep,
      _StateKind.stale => ShodashaTheme.warning,
      _StateKind.error =>
        isNetwork ? ShodashaTheme.warning : ShodashaTheme.danger,
      _StateKind.loading || _StateKind.content => ShodashaTheme.tealDeep,
    };

    return Semantics(
      container: true,
      liveRegion: _kind == _StateKind.error,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: ShodashaTheme.minTarget,
                  height: ShodashaTheme.minTarget,
                  decoration: BoxDecoration(
                    color: tint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 24, color: tone),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  title ?? '',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (message != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (onAction != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: actionLabel ?? 'Retry',
                    kind: AppButtonKind.secondary,
                    onPressed: onAction,
                    expand: false,
                    height: ShodashaTheme.minTarget,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ShodashaTheme.skeleton,
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
      ),
    );
  }
}
