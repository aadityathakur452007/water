import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 48x48 icon action with a real tooltip and an accessible label.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.badge,
    this.color,
    this.backgroundColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final int? badge;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final showBadge = badge != null && badge! > 0;
    final foreground =
        color ?? (selected ? ShodashaTheme.tealDeep : ShodashaTheme.ink);
    final ground =
        backgroundColor ??
        (selected ? ShodashaTheme.tealTint : Colors.transparent);

    return Semantics(
      button: true,
      enabled: onPressed != null,
      selected: selected,
      label: showBadge ? '$tooltip, $badge new' : tooltip,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: ExcludeSemantics(
          child: SizedBox(
            width: ShodashaTheme.minTarget,
            height: ShodashaTheme.minTarget,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  onPressed: onPressed,
                  icon: Icon(icon, size: 24),
                  style: IconButton.styleFrom(
                    foregroundColor: foreground,
                    backgroundColor: ground,
                    disabledForegroundColor: ShodashaTheme.muted,
                    fixedSize: const Size(
                      ShodashaTheme.minTarget,
                      ShodashaTheme.minTarget,
                    ),
                    minimumSize: const Size(
                      ShodashaTheme.minTarget,
                      ShodashaTheme.minTarget,
                    ),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                    ),
                  ),
                ),
                if (showBadge)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IgnorePointer(
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: const BoxDecoration(
                          color: ShodashaTheme.solar,
                          borderRadius: BorderRadius.all(Radius.circular(9)),
                        ),
                        child: Text(
                          badge! > 99 ? '99+' : '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: ShodashaTheme.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
