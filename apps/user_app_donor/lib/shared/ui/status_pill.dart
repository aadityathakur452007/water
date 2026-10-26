import 'package:flutter/material.dart';

import '../../core/theme.dart';

enum StatusPillTone { neutral, info, success, warning, danger, solar }

/// User-facing status chip: icon + sentence-case label + semantic tone.
/// Callers pass the translated label, never a raw enum or status code.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusPillTone.neutral,
    this.icon = Icons.circle,
  });

  final String label;
  final StatusPillTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final (ground, ink, line) = switch (tone) {
      StatusPillTone.neutral => (
        ShodashaTheme.bg,
        ShodashaTheme.muted,
        ShodashaTheme.border,
      ),
      StatusPillTone.info => (
        ShodashaTheme.etaTint,
        ShodashaTheme.link,
        ShodashaTheme.link.withValues(alpha: 0.25),
      ),
      StatusPillTone.success => (
        ShodashaTheme.greenTint,
        ShodashaTheme.successDark,
        ShodashaTheme.greenBorder,
      ),
      StatusPillTone.warning => (
        ShodashaTheme.solarTint,
        ShodashaTheme.warning,
        ShodashaTheme.solarBorder,
      ),
      StatusPillTone.danger => (
        ShodashaTheme.danger.withValues(alpha: 0.08),
        ShodashaTheme.danger,
        ShodashaTheme.danger.withValues(alpha: 0.2),
      ),
      StatusPillTone.solar => (
        ShodashaTheme.solar,
        ShodashaTheme.onSolar,
        ShodashaTheme.solarDark.withValues(alpha: 0.35),
      ),
    };

    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: ground,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: ink),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
