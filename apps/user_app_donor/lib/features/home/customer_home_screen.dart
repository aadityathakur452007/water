// Donor customer home tab. Visual grammar follows the donor home (teal top
// bar, mode cards, featured jars with real images, purity card); data is the
// real catalog / address / subscription state owned by the 032 controllers.
// Clean, decluttered mobile layout without duplicate profile or cart chrome.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui/app_banner.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_card.dart';
import '../../shared/ui/status_pill.dart';
import '../addresses/address_screen.dart';
import '../booking/booking_controller.dart';
import '../orders/orders_controller.dart';
import 'widgets/featured_products.dart';
import 'widgets/live_purity_card.dart';
import 'widgets/mode_selection_cards.dart';
import 'widgets/top_bar.dart';

class DonorHomeTab extends StatefulWidget {
  const DonorHomeTab({
    super.key,
    required this.api,
    required this.booking,
    required this.addresses,
    required this.onInstantOrder,
    required this.onSubscribe,
    required this.onOpenAddresses,
    required this.onOpenNotifications,
    this.onOpenProfile,
    required this.onOpenSupport,
    this.onOpenCart,
    this.orders,
    required this.onOrderProduct,
    this.onOpenOrders,
  });

  final VoidCallback? onOpenOrders;

  final ApiClient api;
  final BookingController booking;
  final AddressController addresses;
  final VoidCallback onInstantOrder;
  final VoidCallback onSubscribe;
  final VoidCallback onOpenAddresses;
  final VoidCallback onOpenNotifications;
  final VoidCallback? onOpenProfile;
  final VoidCallback onOpenSupport;
  final VoidCallback? onOpenCart;
  final OrdersController? orders;
  final void Function({required int refill, required int container})
  onOrderProduct;

  @override
  State<DonorHomeTab> createState() => _DonorHomeTabState();
}

class _DonorHomeTabState extends State<DonorHomeTab> {
  @override
  void initState() {
    super.initState();
    widget.booking.ensureCatalog(HttpCatalogApi(widget.api));
    if (!widget.booking.hasRates) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.booking.refreshRates();
      });
    }
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.booking, widget.addresses]),
      builder: (context, _) {
        final selected = widget.addresses.resolve();
        final addressStatus = widget.addresses.status;
        final ratesOffline = widget.booking.ratesOffline;

        return Column(
          children: [
            DonorTopBar(
              addressLabel: selected?.label,
              addressDetail: selected?.addressLine,
              addressLoading:
                  addressStatus == AddrStatus.loading && selected == null,
              addressError:
                  addressStatus == AddrStatus.error && selected == null,
              addressEmpty:
                  addressStatus == AddrStatus.loaded &&
                  widget.addresses.items.isEmpty,
              onRetryAddress: widget.addresses.load,
              onAddressTap: widget.onOpenAddresses,
              onNotifications: widget.onOpenNotifications,
            ),
            if (ratesOffline)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  0,
                ),
                child: AppBanner.offline(onRetry: widget.booking.refreshRates),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await Future.wait([
                    widget.booking.refreshRates(),
                    widget.addresses.load(),
                  ]);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.md,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$_greeting,',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: ShodashaTheme.muted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Pure water, delivered.',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.6,
                                    height: 1.15,
                                    color: ShodashaTheme.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const StatusPill(
                            label: 'RO + UV',
                            tone: StatusPillTone.brand,
                            icon: Icons.verified_outlined,
                          ),
                        ],
                      ),
                    ),
                    if (widget.orders != null)
                      ListenableBuilder(
                        listenable: widget.orders!,
                        builder: (context, _) {
                          Order? activeOrder;
                          for (final o in widget.orders!.allOrders) {
                            if (o.state == OrderState.dispatched ||
                                o.state == OrderState.assigned ||
                                o.state == OrderState.placed) {
                              activeOrder = o;
                              break;
                            }
                          }
                          if (activeOrder != null) {
                            return _ActiveDeliveryCard(
                              order: activeOrder,
                              onTap: widget.onOpenOrders,
                            );
                          }
                          final candidate = widget.orders!.reorderCandidate;
                          if (candidate == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              0,
                              AppSpacing.lg,
                              AppSpacing.md,
                            ),
                            child: _QuickReorderCard(
                              order: candidate,
                              onReorder: () => widget.onOrderProduct(
                                refill: candidate.refillQty,
                                container: candidate.containerQty,
                              ),
                            ),
                          );
                        },
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: ModeSelectionCards(
                        onInstantOrder: widget.onInstantOrder,
                        onSubscribe: widget.onSubscribe,
                      ),
                    ),
                    if (widget.booking.ratesError != null &&
                        widget.booking.rates != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          0,
                        ),
                        child: AppBanner.stale(
                          message: widget.booking.ratesError,
                          onRetry: widget.booking.refreshRates,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: FeaturedProductsShowcase(
                        rates: widget.booking.rates,
                        loading: widget.booking.ratesLoading,
                        error: widget.booking.ratesError,
                        onRetry: widget.booking.refreshRates,
                        onOrder: widget.onOrderProduct,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const LivePurityCard(),
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: _SupportCard(onTap: widget.onOpenSupport),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: ShodashaTheme.surface,
      borderColor: ShodashaTheme.border,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ShodashaTheme.tealTint,
              shape: BoxShape.circle,
              border: Border.all(
                color: ShodashaTheme.border,
              ),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: ShodashaTheme.tealDeep,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need help with a delivery?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Call or WhatsApp Bhopal support directly',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: ShodashaTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          AppButton(
            label: 'Support',
            kind: AppButtonKind.ghost,
            expand: false,
            height: ShodashaTheme.minTarget,
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}

class _QuickReorderCard extends StatelessWidget {
  const _QuickReorderCard({required this.order, required this.onReorder});

  final Order order;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final summary = order.itemSummary.isEmpty
        ? 'last order'
        : order.itemSummary;
    return AppCard(
      color: ShodashaTheme.tealTint,
      borderColor: ShodashaTheme.teal.withValues(alpha: 0.22),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.replay_rounded,
            color: ShodashaTheme.tealDeep,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reorder last delivery',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  summary,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: ShodashaTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          AppButton(
            label: 'Reorder',
            kind: AppButtonKind.money,
            expand: false,
            height: ShodashaTheme.minTarget,
            onPressed: onReorder,
          ),
        ],
      ),
    );
  }
}


class _ActiveDeliveryCard extends StatelessWidget {
  const _ActiveDeliveryCard({
    required this.order,
    this.onTap,
  });

  final Order order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasOtp = order.deliveryOtp != null && order.deliveryOtp!.isNotEmpty;
    final isDispatched = order.state == OrderState.dispatched;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: ShodashaTheme.surface,
          borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
          border: Border.all(
            color: isDispatched ? ShodashaTheme.teal : ShodashaTheme.border,
            width: isDispatched ? 1.5 : 1.0,
          ),
          boxShadow: ShodashaTheme.subtleCardShadow,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isDispatched ? ShodashaTheme.tealTint : ShodashaTheme.bg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.local_shipping_rounded,
                    color: isDispatched ? ShodashaTheme.teal : ShodashaTheme.muted,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DELIVERY IN PROGRESS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: ShodashaTheme.muted,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        orderStateLabel(order.state),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isDispatched ? ShodashaTheme.tealDark : ShodashaTheme.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ShodashaTheme.tealTint,
                    borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                  ),
                  child: Text(
                    order.itemSummary.isEmpty ? '20L Can' : order.itemSummary,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ShodashaTheme.tealDark,
                    ),
                  ),
                ),
              ],
            ),
            if (hasOtp) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: ShodashaTheme.bg,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                  border: Border.all(color: ShodashaTheme.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pin_rounded, color: ShodashaTheme.teal, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'DELIVERY OTP (SHARE AT DOORSTEP)',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: ShodashaTheme.muted,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            order.deliveryOtp!,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: ShodashaTheme.teal,
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (onTap != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'View details & tracking',
                kind: AppButtonKind.secondary,
                icon: Icons.track_changes_rounded,
                onPressed: onTap,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
