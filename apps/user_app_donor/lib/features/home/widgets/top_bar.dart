// Donor top bar, wired to real state. The address comes from GET /addresses,
// search filters the server catalog, and the badge is the current checkout jar
// count (zero hides it). Loading, error and empty address states are explicit
// so the bar never claims "add address" while a read is still in flight.

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/ui/app_icon_button.dart';

class DonorTopBar extends StatelessWidget {
  const DonorTopBar({
    super.key,
    required this.addressLabel,
    required this.addressDetail,
    required this.cartCount,
    required this.onAddressTap,
    required this.onNotifications,
    required this.onProfile,
    required this.onCart,
    required this.onSearch,
    this.addressLoading = false,
    this.addressError = false,
    this.addressEmpty = false,
    this.onRetryAddress,
  });

  final String? addressLabel;
  final String? addressDetail;
  final int cartCount;
  final VoidCallback onAddressTap;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final VoidCallback onCart;
  final VoidCallback onSearch;
  final bool addressLoading;
  final bool addressError;
  final bool addressEmpty;
  final VoidCallback? onRetryAddress;

  @override
  Widget build(BuildContext context) {
    final hasAddress = (addressLabel ?? '').trim().isNotEmpty;

    final (addressTitle, addressSubtitle) = switch ((
      addressLoading,
      addressError,
      hasAddress,
      addressEmpty,
    )) {
      (true, _, false, _) => ('Loading delivery address…', null),
      (_, true, false, _) => ("Couldn't load address", 'Tap to retry'),
      (_, _, true, _) => ('Deliver to ${addressLabel!.trim()}', addressDetail),
      (_, _, _, true) => (
        'Add a delivery address',
        'Serviceable Bhopal pin codes',
      ),
      _ => ('Add a delivery address', 'Serviceable Bhopal pin codes'),
    };

    return DecoratedBox(
      decoration: const BoxDecoration(color: ShodashaTheme.tealDeep),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.water_drop_rounded,
                  color: ShodashaTheme.surface,
                  size: 24,
                ),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'Shodasha',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: ShodashaTheme.surface,
                    ),
                  ),
                ),
                AppIconButton(
                  icon: Icons.notifications_outlined,
                  tooltip: 'Notifications',
                  onPressed: onNotifications,
                  color: ShodashaTheme.surface,
                  backgroundColor: ShodashaTheme.surface.withValues(
                    alpha: 0.14,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppIconButton(
                  icon: Icons.person_outline_rounded,
                  tooltip: 'Profile',
                  onPressed: onProfile,
                  color: ShodashaTheme.surface,
                  backgroundColor: ShodashaTheme.surface.withValues(
                    alpha: 0.14,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppIconButton(
                  icon: Icons.shopping_bag_outlined,
                  tooltip: cartCount > 0
                      ? 'Checkout, $cartCount jars'
                      : 'Checkout',
                  onPressed: onCart,
                  badge: cartCount > 0 ? cartCount : null,
                  color: ShodashaTheme.surface,
                  backgroundColor: ShodashaTheme.surface.withValues(
                    alpha: 0.14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              button: true,
              label: addressTitle,
              hint: addressError ? 'Retry loading your address' : null,
              child: InkWell(
                onTap: addressError
                    ? (onRetryAddress ?? onAddressTap)
                    : onAddressTap,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: ShodashaTheme.minTarget,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          addressError
                              ? Icons.location_off_outlined
                              : Icons.location_on_outlined,
                          color: ShodashaTheme.surface,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (addressLoading)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.8,
                                          color: ShodashaTheme.surface,
                                        ),
                                      ),
                                    ),
                                  Flexible(
                                    child: Text(
                                      addressTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: ShodashaTheme.surface,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if ((addressSubtitle ?? '').trim().isNotEmpty)
                                Text(
                                  addressSubtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: ShodashaTheme.surface.withValues(
                                      alpha: 0.82,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (addressError)
                          Text(
                            'Retry',
                            style: TextStyle(
                              color: ShodashaTheme.surface.withValues(
                                alpha: 0.92,
                              ),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: ShodashaTheme.surface,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Material(
              color: ShodashaTheme.surface,
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
              child: InkWell(
                onTap: onSearch,
                borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                child: SizedBox(
                  height: ShodashaTheme.minTarget,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search_rounded,
                          color: ShodashaTheme.muted,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Search water cans',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ShodashaTheme.muted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const Text(
                          '20L',
                          style: TextStyle(
                            color: ShodashaTheme.tealDeep,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
