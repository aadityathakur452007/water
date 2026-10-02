// F3 — Custom stepper (minus/value/plus). 48dp targets, radius 8, flat.
// Motion: opacity/transform only, press scale 0.97, 150ms (emil-design-eng).

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Shodasha tokens (flat, no shadows/gradients) — aliases of
/// [ShodashaTheme] (Wave 1 honesty: local #0369A1 drifted, locked is #0284C7).
class ShodashaColors {
  static const Color bg = ShodashaTheme.bg;
  static const Color ink = ShodashaTheme.ink;
  static const Color muted = ShodashaTheme.muted;
  static const Color accent = ShodashaTheme.blue;
  static const Color accentSoft = ShodashaTheme.blueTint;
  static const Color border = ShodashaTheme.border;
}

const double kShodashaRadius = 8;

/// Press wrapper: scale 0.97 on pointer-down (transform only, 150ms).
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  double _scale = 1;

  void _down(TapDownDetails _) => setState(() => _scale = 0.97);
  void _up() => setState(() => _scale = 1);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : _down,
      onTapUp: widget.onTap == null ? null : (_) => _up(),
      onTapCancel: _up,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scaleByDouble(_scale, _scale, 1, 1),
        transformAlignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}

/// Custom quantity stepper: [-] value [+]. Clamps 0–10 (caller enforces).
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 10,
    this.semanticsLabel = 'quantity',
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final String semanticsLabel;

  void _step(int delta) {
    final next = (value + delta).clamp(min, max);
    if (next != value) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      value: '$value',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: Icons.remove,
            label: '$semanticsLabel kam karein',
            enabled: value > min,
            onTap: value > min ? () => _step(-1) : null,
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            alignment: Alignment.center,
            child: Text(
              '$value',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ShodashaColors.ink,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            label: '$semanticsLabel badhayein',
            enabled: value < max,
            onTap: value < max ? () => _step(1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget box = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: enabled ? ShodashaColors.accentSoft : ShodashaColors.bg,
        border: Border.all(color: ShodashaColors.border),
        borderRadius: BorderRadius.circular(kShodashaRadius),
      ),
      child: Icon(
        icon,
        color: enabled ? ShodashaColors.accent : ShodashaColors.muted,
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: enabled
          ? PressScale(
              onTap: onTap,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: enabled ? 1 : 0.5,
                child: box,
              ),
            )
          : Opacity(opacity: 0.5, child: box),
    );
  }
}
