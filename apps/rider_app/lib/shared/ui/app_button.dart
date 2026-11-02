import 'package:flutter/material.dart';
import '../../core/theme.dart';

enum AppButtonKind {
  primary,
  secondary,
  money,
  danger,
}

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = AppButtonKind.primary,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    BorderSide side = BorderSide.none;

    switch (kind) {
      case AppButtonKind.primary:
        bg = ShodashaTheme.teal;
        fg = Colors.white;
      case AppButtonKind.secondary:
        bg = ShodashaTheme.surface;
        fg = ShodashaTheme.ink;
        side = const BorderSide(color: ShodashaTheme.border, width: 1.5);
      case AppButtonKind.money:
        bg = ShodashaTheme.successDark;
        fg = Colors.white;
      case AppButtonKind.danger:
        bg = ShodashaTheme.danger;
        fg = Colors.white;
    }

    final disabled = onPressed == null || busy;

    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: disabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: ShodashaTheme.border,
          disabledForegroundColor: ShodashaTheme.muted,
          elevation: 0,
          side: side,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        ),
        child: busy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: disabled ? ShodashaTheme.muted : fg,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
