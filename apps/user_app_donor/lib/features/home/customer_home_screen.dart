// ignore_for_file: deprecated_member_use

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
                                const Text(
                                  '20L RO + UV delivery',
                                  style: TextStyle(
                                    fontSize: 13,
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
                          Order? recentFailedOrder;
                          Order? staleOrder;
                          final now = DateTime.now();
                          for (final o in widget.orders!.allOrders) {
                            if (o.state == OrderState.dispatched ||
                                o.state == OrderState.assigned ||
                                o.state == OrderState.placed ||
                                o.state == OrderState.packed) {
                              if (o.isStaleDelivery) {
                                staleOrder ??= o;
                              } else {
                                activeOrder ??= o;
                              }
                            }
                            if (recentFailedOrder == null &&
                                o.state == OrderState.failed &&
                                o.windowStart.isBefore(now) &&
                                now.difference(o.windowStart).inHours < 24) {
                              recentFailedOrder = o;
                            }
                          }
                          if (staleOrder != null) {
                            return _StaleDeliveryReconciliationCard(
                              order: staleOrder,
                              controller: widget.orders!,
                              onCompleted: () => widget.orders!.refreshOrder(staleOrder!.id),
                            );
                          }
                          if (activeOrder != null) {
                            return _ActiveDeliveryCard(
                              order: activeOrder,
                              onTap: widget.onOpenOrders,
                            );
                          }
                          if (recentFailedOrder != null) {
                            return _FailedDeliveryNoticeCard(
                              order: recentFailedOrder,
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

class _FailedDeliveryNoticeCard extends StatelessWidget {
  const _FailedDeliveryNoticeCard({
    required this.order,
    this.onTap,
  });

  final Order order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final reasonText =
        (order.failureReason != null && order.failureReason!.isNotEmpty)
            ? formatFailureReason(order.failureReason)
            : 'Delivery could not be completed';

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
            color: ShodashaTheme.danger.withValues(alpha: 0.35),
            width: 1.2,
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
                    color: ShodashaTheme.danger.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: ShodashaTheme.danger,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DELIVERY ATTEMPT FAILED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: ShodashaTheme.danger,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        reasonText,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: ShodashaTheme.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Our delivery partner was unable to complete the delivery. Tap to view details or contact support.',
              style: TextStyle(
                fontSize: 12,
                color: ShodashaTheme.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'View order details',
                kind: AppButtonKind.secondary,
                icon: Icons.info_outline_rounded,
                onPressed: onTap,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StaleDeliveryReconciliationCard extends StatefulWidget {
  const _StaleDeliveryReconciliationCard({
    required this.order,
    required this.controller,
    required this.onCompleted,
  });

  final Order order;
  final OrdersController controller;
  final VoidCallback onCompleted;

  @override
  State<_StaleDeliveryReconciliationCard> createState() =>
      _StaleDeliveryReconciliationCardState();
}

class _StaleDeliveryReconciliationCardState
    extends State<_StaleDeliveryReconciliationCard> {
  bool _busy = false;

  Future<void> _handleYesReceived() async {
    final isCod = widget.order.paymentMode.toLowerCase() == 'cod';
    bool cashPaid = true;

    if (isCod && widget.order.totalPaise > 0) {
      final picked = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          bool paid = true;
          return StatefulBuilder(
            builder: (ctx, setS) => Container(
              decoration: const BoxDecoration(
                color: ShodashaTheme.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Doorstep Payment (COD)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ShodashaTheme.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Total amount: ₹${(widget.order.totalPaise / 100).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ShodashaTheme.teal,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Did you pay cash to the delivery partner?',
                    style: TextStyle(fontSize: 14, color: ShodashaTheme.muted),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  RadioListTile<bool>(
                    value: true,
                    groupValue: paid,
                    onChanged: (v) => setS(() => paid = v ?? true),
                    title: const Text('Yes, I paid cash to delivery partner'),
                  ),
                  RadioListTile<bool>(
                    value: false,
                    groupValue: paid,
                    onChanged: (v) => setS(() => paid = v ?? false),
                    title: const Text('No, add to my next water bill'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      label: 'Confirm & Complete',
                      onPressed: () => Navigator.of(ctx).pop(paid),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (picked == null || !mounted) return;
      cashPaid = picked;
    }

    setState(() => _busy = true);
    final ok = await widget.controller.confirmDelivery(
      widget.order.id,
      received: true,
      cashPaid: cashPaid,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery confirmed! 20L jar added to your account.'),
          backgroundColor: ShodashaTheme.teal,
        ),
      );
      widget.onCompleted();
    }
  }

  Future<void> _handleNotReceived() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: ShodashaTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Water Jar Not Delivered',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ShodashaTheme.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'We apologize for the delay. How would you like us to proceed?',
              style: TextStyle(fontSize: 13, color: ShodashaTheme.muted),
            ),
            const SizedBox(height: AppSpacing.lg),
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined, color: ShodashaTheme.teal),
              title: const Text('Deliver Today Morning', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Reschedule to today morning route (7 AM - 12 PM)'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                side: const BorderSide(color: ShodashaTheme.border),
              ),
              onTap: () => Navigator.of(ctx).pop('reschedule'),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: const Icon(Icons.cancel_outlined, color: ShodashaTheme.danger),
              title: const Text('Cancel Order', style: TextStyle(fontWeight: FontWeight.w700, color: ShodashaTheme.danger)),
              subtitle: const Text('Cancel this order with no cancellation fees'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                side: const BorderSide(color: ShodashaTheme.border),
              ),
              onTap: () => Navigator.of(ctx).pop('cancel'),
            ),
          ],
        ),
      ),
    );

    if (action == null || !mounted) return;
    setState(() => _busy = true);
    final ok = await widget.controller.confirmDelivery(
      widget.order.id,
      received: false,
      rescheduleToday: action == 'reschedule',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'reschedule'
              ? 'Order rescheduled for today morning route!'
              : 'Order cancelled successfully.'),
          backgroundColor: ShodashaTheme.ink,
        ),
      );
      widget.onCompleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        border: Border.all(color: ShodashaTheme.solarBorder, width: 1.5),
        boxShadow: ShodashaTheme.subtleCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: ShodashaTheme.solarTint,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.help_outline_rounded, size: 14, color: ShodashaTheme.warning),
                    SizedBox(width: 4),
                    Text(
                      'DELIVERY CHECK',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: ShodashaTheme.warning,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Order #${widget.order.id.length > 8 ? widget.order.id.substring(0, 8).toUpperCase() : widget.order.id}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ShodashaTheme.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Did you receive your 20L water jar?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ShodashaTheme.ink,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Your delivery was scheduled for yesterday. Please confirm if the delivery partner handed over the jar.',
            style: TextStyle(
              fontSize: 12,
              color: ShodashaTheme.muted,
              height: 1.3,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_busy)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Yes, received',
                    kind: AppButtonKind.primary,
                    icon: Icons.check_circle_outline_rounded,
                    onPressed: _handleYesReceived,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    label: 'No, not yet',
                    kind: AppButtonKind.secondary,
                    icon: Icons.highlight_off_rounded,
                    onPressed: _handleNotReceived,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
