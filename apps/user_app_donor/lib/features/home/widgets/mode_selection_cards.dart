// Donor mode cards, with the local "instant order" sheet removed. Both cards
// now navigate into the real checkout/subscription flows.

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';

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
    return Row(
      children: [
        Expanded(
          child: _card(
            color: AppColors.primary,
            glow: AppColors.primary.withValues(alpha: 0.25),
            icon: Icons.bolt_rounded,
            iconColor: Colors.white,
            title: 'Instant Delivery',
            subtitle: 'Get water within 45 mins',
            titleColor: Colors.white,
            subtitleColor: Colors.white70,
            onTap: onInstantOrder,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _card(
            color: AppColors.accent,
            glow: AppColors.accent.withValues(alpha: 0.25),
            icon: Icons.calendar_month_rounded,
            iconColor: AppColors.textOnAccent,
            title: 'Subscription',
            subtitle: 'Daily / alternate schedule',
            titleColor: AppColors.textOnAccent,
            subtitleColor: const Color(0xFF78350F),
            onTap: onSubscribe,
          ),
        ),
      ],
    );
  }

  Widget _card({
    required Color color,
    required Color glow,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color titleColor,
    required Color subtitleColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppConstants.cardBorderRadius),
          boxShadow: [
            BoxShadow(color: glow, blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 26),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: titleColor,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: subtitleColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
