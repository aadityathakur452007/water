import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Elevated/Flat card: 16 radius, 1px border, 2dp subtle drop shadow, 16dp padding.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.color = ShodashaTheme.surface,
    this.borderColor = ShodashaTheme.border,
    this.elevation = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final bool elevation;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(ShodashaTheme.radiusLg);
    final content = Padding(padding: padding, child: child);

    return Semantics(
      container: true,
      button: onTap != null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: elevation ? ShodashaTheme.subtleCardShadow : null,
        ),
        child: Material(
          color: color,
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: borderColor),
          ),
          child: onTap == null ? content : InkWell(onTap: onTap, child: content),
        ),
      ),
    );
  }
}
