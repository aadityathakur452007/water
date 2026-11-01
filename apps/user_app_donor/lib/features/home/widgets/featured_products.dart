// Donor featured-products list, fed by the server catalog. Prices and deposit
// come from GET /catalog; ordering opens the real quote -> order checkout.
// Real 20L can imagery (assets/20l.jpg), 48dp minimum touch targets,
// and quiet, unsloped mobile cards without generic placeholder icons.

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
            'Daily verified',
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
            subtitle: 'Exchange empty jar at delivery · RO + UV purified',
            price: formatInr(rates!.refillPaise),
            tag: 'Bestseller',
            icon: Icons.water_drop_outlined,
            imageAsset: 'assets/20l.jpg',
            actionLabel: 'Order',
            onTap: () => onOrder(refill: 1, container: 0),
          ),
          const SizedBox(height: AppSpacing.md),
          _ProductCard(
            title: '20L can + new jar',
            subtitle:
                'Includes ${formatInr(rates!.depositPaise)} refundable jar deposit',
            price: formatInr(rates!.containerPaise),
            tag: 'First order',
            icon: Icons.local_drink_outlined,
            imageAsset: 'assets/20l.jpg',
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
    this.imageAsset,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String price;
  final String tag;
  final IconData icon;
  final String? imageAsset;
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
              ClipRRect(
                borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                child: Container(
                  height: 54,
                  width: 54,
                  color: ShodashaTheme.tealTint,
                  child: imageAsset != null
                      ? Image.asset(
                          imageAsset!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            icon,
                            color: ShodashaTheme.tealDeep,
                            size: 26,
                          ),
                        )
                      : Icon(
                          icon,
                          color: ShodashaTheme.tealDeep,
                          size: 26,
                        ),
                ),
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
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
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
                        fontSize: 12,
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
