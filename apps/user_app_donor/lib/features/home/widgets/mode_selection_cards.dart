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
              ground: ShodashaTheme.tealDeep,
              foreground: ShodashaTheme.surface,
              icon: Icons.bolt_rounded,
              eyebrow: 'One delivery',
              title: 'Instant order',
              subtitle: 'Pick a 30-min slot',
              onTap: onInstantOrder,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _ModeCard(
              ground: ShodashaTheme.solarTint,
              foreground: ShodashaTheme.ink,
              icon: Icons.event_repeat_rounded,
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
    required this.ground,
    required this.foreground,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color ground;
  final Color foreground;
  final IconData icon;
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
        color: ground,
        borderRadius: radius,
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
                          color: foreground.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: foreground, size: 20),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_outward_rounded,
                        color: foreground.withValues(alpha: 0.85),
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    eyebrow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12.5,
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
