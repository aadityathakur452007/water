// Donor featured-products list, fed by the server catalog. Prices and deposit
// come from GET /catalog; ordering opens the real quote -> order checkout.
// Cards use Material press feedback, 48dp actions and readable labels.

import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../shared/ui/app_button.dart';
import '../../../shared/ui/app_card.dart';
import '../../../shared/ui/app_state_view.dart';
import '../../../shared/ui/section_header.dart';
import '../../booking/booking_controller.dart';

class FeaturedProductsShowcase extends StatelessWidget {
  const FeaturedProductsShowcase({
    super.key,
    required this.rates,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onOrder,
  });

  final CatalogRates? rates;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final void Function({required int refill, required int container}) onOrder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Featured water cans',
          trailing: const Text(
            'Server prices',
            style: TextStyle(
              fontSize: 12,
              color: ShodashaTheme.tealDeep,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (loading && rates == null)
          const _ProductsSkeleton()
        else if (error != null && rates == null)
          AppStateView.error(
            title: 'Prices unavailable',
            message: error,
            onRetry: onRetry,
          )
        else if (rates != null) ...[
          _ProductCard(
            title: '20L refill can',
            subtitle: 'Bring your own jar · RO + UV purified',
            price: formatInr(rates!.refillPaise),
            tag: 'Bestseller',
            icon: Icons.water_drop_outlined,
            actionLabel: 'Order',
            onTap: () => onOrder(refill: 1, container: 0),
          ),
          const SizedBox(height: AppSpacing.md),
          _ProductCard(
            title: '20L can + new jar',
            subtitle:
                'Refundable deposit ${formatInr(rates!.depositPaise)} · '
                'return the jar to get it back',
            price: formatInr(rates!.containerPaise),
            tag: 'First order',
            icon: Icons.local_drink_outlined,
            actionLabel: 'Order',
            onTap: () => onOrder(refill: 0, container: 1),
          ),
        ],
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.tag,
    required this.icon,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String price;
  final String tag;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: ShodashaTheme.tealTint,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                ),
                child: Icon(icon, color: ShodashaTheme.tealDeep, size: 26),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              height: 1.25,
                              color: ShodashaTheme.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: ShodashaTheme.solarTint,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: ShodashaTheme.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: ShodashaTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  price,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: ShodashaTheme.ink,
                  ),
                ),
              ),
              AppButton(
                label: actionLabel,
                kind: AppButtonKind.secondary,
                expand: false,
                height: ShodashaTheme.minTarget,
                onPressed: onTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductsSkeleton extends StatelessWidget {
  const _ProductsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(2, (i) {
        return Container(
          height: 136,
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          decoration: BoxDecoration(
            color: ShodashaTheme.surface,
            borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
            border: Border.all(color: ShodashaTheme.border),
          ),
        );
      }),
    );
  }
}
