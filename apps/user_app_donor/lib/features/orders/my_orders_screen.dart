// Donor orders screen, backed by the real cursor-paged OrdersController.
// The donor screen only listed a local `activeOrders` list; this one keeps
// the "LIVE DELIVERIES" grammar and also shows real closed orders so the
// customer can retrieve bills. No local status/PIN/rider data is used.

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import 'bill_screen.dart';
import 'order_card.dart';
import 'orders_controller.dart';
import 'tracking_screen.dart';

class DonorOrdersScreen extends StatefulWidget {
  const DonorOrdersScreen({
    super.key,
    required this.controller,
    this.onSupport,
  });

  final OrdersController controller;
  final VoidCallback? onSupport;

  @override
  State<DonorOrdersScreen> createState() => _DonorOrdersScreenState();
}

class _DonorOrdersScreenState extends State<DonorOrdersScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.status == OrdersListStatus.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.load();
      });
    }
  }

  Future<void> _track(Order order) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TrackingScreen(
          controller: widget.controller,
          orderId: order.id,
          onSupport: widget.onSupport,
        ),
      ),
    );
  }

  void _bill(Order order) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => BillScreen(order: order)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'MY WATER ORDERS',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: Colors.white,
            letterSpacing: 1.1,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: widget.controller.load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          if (c.status == OrdersListStatus.loading && c.totalCount == 0) {
            return const _OrdersSkeleton();
          }
          if (c.status == OrdersListStatus.error && c.totalCount == 0) {
            return _OrdersError(
              message: c.errorMessage ?? 'Could not load orders.',
              onRetry: c.load,
            );
          }
          final all = c.allOrders;
          final active = all.where(_isActive).toList();
          final closed = all.where((o) => !_isActive(o)).toList();
          return RefreshIndicator(
            onRefresh: c.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              children: [
                if (c.isOffline)
                  const _StaleNote(
                    message: 'Offline — showing the orders already loaded.',
                  )
                else if (c.errorMessage != null && !c.loadMoreFailed)
                  _StaleNote(
                    message: c.isServerError
                        ? 'Server problem — showing the orders already loaded.'
                        : 'Could not refresh — showing the orders already loaded.',
                    onRetry: c.load,
                  ),
                _sectionTitle('LIVE DELIVERIES'),
                const SizedBox(height: 10),
                if (active.isEmpty)
                  const _EmptyBlock(
                    icon: Icons.local_shipping_outlined,
                    title: 'No active deliveries right now.',
                    hint: 'Your next order will appear here with live status.',
                  )
                else
                  ...active.map(
                    (o) => DonorOrderCard(
                      order: o,
                      onTrack: () => _track(o),
                      onBill: () => _bill(o),
                    ),
                  ),
                if (closed.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionTitle('PAST ORDERS'),
                  const SizedBox(height: 10),
                  ...closed.map(
                    (o) => DonorOrderCard(
                      order: o,
                      onTrack: () => _track(o),
                      onBill: () => _bill(o),
                    ),
                  ),
                ],
                if (c.hasMore) ...[
                  const SizedBox(height: 4),
                  OutlinedButton(
                    onPressed: c.loadingMore ? null : c.loadMore,
                    child: Text(
                      c.loadingMore ? 'Loading…' : 'Load older orders',
                    ),
                  ),
                ],
                if (c.loadMoreFailed)
                  TextButton(
                    onPressed: c.retryLoadMore,
                    child: const Text('Could not load more — retry'),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  static bool _isActive(Order o) => !{
    OrderState.delivered,
    OrderState.cancelled,
    OrderState.rejected,
    OrderState.failed,
  }.contains(o.state);

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w900,
        color: AppColors.textSecondary,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _StaleNote extends StatelessWidget {
  const _StaleNote({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.fromLTRB(10, 6, onRetry == null ? 10 : 4, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF9C3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE047)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Color(0xFF713F12)),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 30),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersError extends StatelessWidget {
  const _OrdersError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 36,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _OrdersSkeleton extends StatelessWidget {
  const _OrdersSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(
        3,
        (_) => Container(
          height: 180,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
        ),
      ),
    );
  }
}
