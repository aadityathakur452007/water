// Donor orders screen, backed by the real cursor-paged OrdersController.
// Active and past orders share one card grammar; the empty state offers the
// first-order path, and pagination failures stay in the footer.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/ui/app_banner.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_state_view.dart';
import '../../shared/ui/section_header.dart';
import 'bill_screen.dart';
import 'order_card.dart';
import 'orders_controller.dart';
import 'tracking_screen.dart';

class DonorOrdersScreen extends StatefulWidget {
  const DonorOrdersScreen({
    super.key,
    required this.controller,
    this.onSupport,
    this.onStartOrder,
  });

  final OrdersController controller;
  final VoidCallback? onSupport;
  final VoidCallback? onStartOrder;

  @override
  State<DonorOrdersScreen> createState() => _DonorOrdersScreenState();
}

class _DonorOrdersScreenState extends State<DonorOrdersScreen> {
  bool _pushing = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller.status == OrdersListStatus.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.load();
      });
    }
  }

  Future<void> _push(Widget page) async {
    if (_pushing) return;
    _pushing = true;
    try {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
    } finally {
      _pushing = false;
    }
  }

  void _track(Order order) => _push(
    TrackingScreen(
      controller: widget.controller,
      orderId: order.id,
      onSupport: widget.onSupport,
    ),
  );

  void _bill(Order order) => _push(BillScreen(order: order));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(
        backgroundColor: ShodashaTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: ShodashaTheme.border)),
        title: const Text(
          'My orders',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: ShodashaTheme.ink,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh orders',
            onPressed: widget.controller.load,
            icon: const Icon(Icons.refresh_rounded, color: ShodashaTheme.ink),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          if (c.status == OrdersListStatus.loading && c.totalCount == 0) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                AppStateView.loading(lines: 4, message: 'Loading your orders'),
              ],
            );
          }
          if (c.status == OrdersListStatus.error && c.totalCount == 0) {
            return AppStateView.error(
              isNetwork: c.isOffline,
              title: c.isOffline ? null : 'Could not load orders',
              message: c.errorMessage,
              onRetry: c.load,
            );
          }
          final all = c.allOrders;
          final active = all.where(_isActive).toList();
          final closed = all.where((o) => !_isActive(o)).toList();
          return RefreshIndicator(
            color: ShodashaTheme.tealDeep,
            onRefresh: c.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                if (c.isOffline)
                  AppBanner.offline(
                    message: 'New orders may not appear until you reconnect.',
                    onRetry: c.refresh,
                  )
                else if (c.errorMessage != null)
                  AppBanner.stale(
                    message: c.isServerError
                        ? 'Server problem — showing the orders already loaded.'
                        : 'Could not refresh — showing the orders already loaded.',
                    onRetry: c.load,
                  ),
                if (all.isEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  AppStateView.empty(
                    icon: Icons.receipt_long_outlined,
                    title: 'No orders yet',
                    message:
                        'Your first 20L jar is a few taps away. Every delivery '
                        'shows up here with live status.',
                    actionLabel: widget.onStartOrder == null
                        ? null
                        : 'Book water',
                    onAction: widget.onStartOrder,
                  ),
                ] else ...[
                  SectionHeader(
                    title: 'Active',
                    padding: const EdgeInsets.only(
                      top: AppSpacing.xs,
                      bottom: AppSpacing.sm,
                    ),
                  ),
                  if (active.isEmpty)
                    AppStateView.empty(
                      icon: Icons.local_shipping_outlined,
                      title: 'No active deliveries',
                      message:
                          'Your next order will appear here with live status.',
                    )
                  else
                    ...active.map(_card),
                  if (closed.isNotEmpty) ...[
                    SectionHeader(title: 'Past orders'),
                    ...closed.map(_card),
                  ],
                ],
                if (c.hasMore) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Load older orders',
                    kind: AppButtonKind.secondary,
                    busy: c.loadingMore,
                    onPressed: c.loadingMore ? null : c.loadMore,
                  ),
                ],
                if (c.loadMoreFailed) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppBanner.stale(
                    message: c.loadMoreError ?? 'Could not load more orders.',
                    onRetry: c.retryLoadMore,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _card(Order o) => DonorOrderCard(
    order: o,
    onTrack: () => _track(o),
    onBill: () => _bill(o),
    onSupport: widget.onSupport,
  );

  static bool _isActive(Order o) => !{
    OrderState.delivered,
    OrderState.cancelled,
    OrderState.rejected,
    OrderState.failed,
  }.contains(o.state);
}
