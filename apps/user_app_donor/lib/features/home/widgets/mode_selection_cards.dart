// Donor mode cards. Both cards navigate into real checkout/subscription flows
// and use Material press/focus feedback instead of raw GestureDetector.

import 'package:flutter/material.dart';

import '../../../core/theme.dart';

class ModeSelectionCards extends StatelessWidget {
  const ModeSelectionCards({
    super.key,
    required this.onInstantOrder,
    required this.onSubscribe,
  });

  final VoidCallback onInstantOrder;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ModeCard(
              icon: Icons.bolt_rounded,
              iconColor: ShodashaTheme.tealDeep,
              iconBg: ShodashaTheme.tealTint,
              eyebrow: 'One delivery',
              title: 'Instant order',
              subtitle: 'Pick a 30-min slot',
              onTap: onInstantOrder,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _ModeCard(
              icon: Icons.event_repeat_rounded,
              iconColor: ShodashaTheme.tealDeep,
              iconBg: ShodashaTheme.tealTint,
              eyebrow: 'Regular delivery',
              title: 'Subscribe',
              subtitle: 'Set a repeat plan',
              onTap: onSubscribe,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String eyebrow;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(ShodashaTheme.radiusLg);
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: ShodashaTheme.surface,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: ShodashaTheme.border),
          borderRadius: radius,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ShodashaTheme.minTarget * 2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: iconBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: iconColor, size: 20),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.arrow_outward_rounded,
                        color: ShodashaTheme.muted,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    eyebrow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ShodashaTheme.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ShodashaTheme.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ShodashaTheme.muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
