// Donor purity card, minus fake live telemetry. The API has no plant telemetry
// endpoint, so this card shows only product facts the rest of the app relies on.

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/ui/app_card.dart';
import '../../../shared/ui/status_pill.dart';

class LivePurityCard extends StatelessWidget {
  const LivePurityCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: ShodashaTheme.tealTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.water_drop_outlined,
                    color: ShodashaTheme.tealDeep,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'Water quality',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ShodashaTheme.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const StatusPill(
                  label: 'Lab-tested',
                  tone: StatusPillTone.success,
                  icon: Icons.verified_outlined,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md,
                horizontal: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: ShodashaTheme.bg,
                borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                border: Border.all(color: ShodashaTheme.border),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Fact(
                      value: '9-stage',
                      title: 'Purification',
                      detail: 'RO + UV + Ozone',
                    ),
                  ),
                  _FactDivider(),
                  Expanded(
                    child: _Fact(
                      value: '20L',
                      title: 'Sealed jar',
                      detail: 'Food-grade',
                    ),
                  ),
                  _FactDivider(),
                  Expanded(
                    child: _Fact(
                      value: 'On request',
                      title: 'Lab report',
                      detail: 'Ask support',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactDivider extends StatelessWidget {
  const _FactDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 44, width: 1, color: ShodashaTheme.border);
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.value, required this.title, required this.detail});

  final String value;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ShodashaTheme.tealDeep,
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ShodashaTheme.ink,
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          detail,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ShodashaTheme.muted,
            fontSize: 11,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}
