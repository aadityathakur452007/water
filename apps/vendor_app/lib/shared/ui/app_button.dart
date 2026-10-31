import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Vendor button intents — ink for logistics CTAs, success for money-received actions.
enum AppButtonKind { primary, secondary, money, danger, ghost }

/// Vendor CTA: 48dp minimum, busy/disabled states, one semantic label.
/// Mirrors donor AppButton API while using vendor's ink/blue design identity.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = AppButtonKind.primary,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final buttonHeight =
        height < ShodashaTheme.minTarget ? ShodashaTheme.minTarget : height;
    final interactive = !busy && onPressed != null;

    final fill = switch (kind) {
      AppButtonKind.primary => ShodashaTheme.ink,
      AppButtonKind.money => ShodashaTheme.success,
      AppButtonKind.danger => ShodashaTheme.danger,
      AppButtonKind.secondary => ShodashaTheme.bg,
      AppButtonKind.ghost => Colors.transparent,
    };
    final foreground = switch (kind) {
      AppButtonKind.primary ||
      AppButtonKind.money ||
      AppButtonKind.danger =>
        ShodashaTheme.bg,
      AppButtonKind.secondary => ShodashaTheme.ink,
      AppButtonKind.ghost => ShodashaTheme.blue,
    };
    final disabledFill =
        kind == AppButtonKind.secondary || kind == AppButtonKind.ghost
            ? fill
            : ShodashaTheme.ink.withValues(alpha: 0.3);

    final style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return busy ? fill : disabledFill;
        }
        return fill;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled) && !busy) {
          return ShodashaTheme.muted;
        }
        return foreground;
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return foreground.withValues(alpha: 0.14);
        }
        if (states.contains(WidgetState.focused) ||
            states.contains(WidgetState.hovered)) {
          return foreground.withValues(alpha: 0.08);
        }
        return null;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (kind == AppButtonKind.secondary) {
          return BorderSide(
            color: states.contains(WidgetState.disabled)
                ? ShodashaTheme.border
                : ShodashaTheme.ink,
          );
        }
        if (kind == AppButtonKind.ghost) return BorderSide.none;
        if (states.contains(WidgetState.focused)) {
          return const BorderSide(color: ShodashaTheme.ink, width: 2);
        }
        return BorderSide.none;
      }),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      minimumSize: WidgetStatePropertyAll(
        Size(interactive ? ShodashaTheme.minTarget : 0, buttonHeight),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
      tapTargetSize: MaterialTapTargetSize.padded,
    );

    final content = busy
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          );

    final button = switch (kind) {
      AppButtonKind.secondary => OutlinedButton(
          onPressed: interactive ? onPressed : null,
          style: style,
          child: content,
        ),
      AppButtonKind.ghost => TextButton(
          onPressed: interactive ? onPressed : null,
          style: style,
          child: content,
        ),
      AppButtonKind.primary ||
      AppButtonKind.money ||
      AppButtonKind.danger =>
        FilledButton(
          onPressed: interactive ? onPressed : null,
          style: style,
          child: content,
        ),
    };

    return Semantics(
      button: true,
      enabled: interactive,
      label: label,
      value: busy ? 'Busy' : null,
      child: ExcludeSemantics(
        child: SizedBox(
          width: expand ? double.infinity : null,
          height: buttonHeight,
          child: button,
        ),
      ),
    );
  }
}
