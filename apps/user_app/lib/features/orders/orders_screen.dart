// F4 — Orders list screen (search + cursor list + skeleton + empty +
// error/offline rows). Contract §4.4 + flows 3/5.
//
// States.md covered: loading (skeleton) / empty / no-results / error /
// offline / refreshing / searching. Search filters client-side (no `q`
// server param). Status is a FLAT solid chip (blueTint bg + blue text + dot).

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'bill_screen.dart';
import 'orders_controller.dart';
import 'tracking_screen.dart';

/// Search + cursor-paged order list (repeat-first: reorder buttons).
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.controller, this.onReorder});

  final OrdersController controller;

  /// One-tap repeat: fills the booking lines from [order], then opens
  /// checkout (caller). Null = reorder hidden (guest wiring pending).
  final ValueChanged<Order>? onReorder;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
    if (widget.controller.status == OrdersListStatus.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.load();
      });
    }
  }

  void _onSearch() => widget.controller.setQuery(_search.text);

  @override
  void dispose() {
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  Future<void> _openTracking(Order order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrackingScreen(
          controller: widget.controller,
          orderId: order.id,
        ),
      ),
    );
  }

  /// First-vs-repeat tag (honest scope: only when createdAt exists on all
  /// rows; legacy rows without timestamps get no tag, never a guessed one).
  bool _isFirstOrder(List<Order> orders, Order order) {
    if (orders.any((o) => o.createdAt == null)) return false;
    Order oldest = orders.first;
    for (final o in orders) {
      if (o.createdAt!.isBefore(oldest.createdAt!)) oldest = o;
    }
    return identical(oldest, order) || oldest.id == order.id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OrdersTokens.white,
      appBar: AppBar(
        backgroundColor: OrdersTokens.white,
        elevation: 0,
        title: Text(
          ordersStringsHi['ordersTitle']!,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: OrdersTokens.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                // WHY: 16px stops iOS auto-zoom (mobile-native §4).
                style: const TextStyle(fontSize: 16, color: OrdersTokens.ink),
                decoration: InputDecoration(
                  labelText: ordersStringsHi['searchHint'],
                  hintText: ordersStringsHi['searchHint'],
                  hintStyle: const TextStyle(color: OrdersTokens.muted),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: OrdersTokens.muted,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(OrdersTokens.radius),
                    borderSide: const BorderSide(color: OrdersTokens.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(OrdersTokens.radius),
                    borderSide: const BorderSide(color: OrdersTokens.blue),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final c = widget.controller;
                  if (c.status == OrdersListStatus.loading &&
                      c.totalCount == 0) {
                    return const _SkeletonList();
                  }
                  if (c.status == OrdersListStatus.error &&
                      c.totalCount == 0) {
                    return _ErrorRow(
                      message: c.errorMessage ??
                          ordersStringsHi['errorTitle']!,
                      onRetry: c.load,
                    );
                  }
                  final orders = c.filteredOrders;
                  if (orders.isEmpty && c.query.trim().isNotEmpty) {                    return _EmptyState(
                      title: ordersStringsHi['noResultsTitle']!,
                      hint: ordersStringsHi['noResultsHint']!,
                    );
                  }
                  if (orders.isEmpty) {
                    return _EmptyState(
                      title: ordersStringsHi['emptyTitle']!,
                      hint: ordersStringsHi['emptyHint']!,
                    );
                  }
                  return RefreshIndicator(
                    color: OrdersTokens.blue,
                    onRefresh: c.refresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: orders.length +
                          (c.hasMore ? 1 : 0) +
                          (c.isOffline ? 1 : 0),
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (c.isOffline && i == 0) {
                          return const _OfflineBanner();
                        }
                        final idx = c.isOffline ? i - 1 : i;
                        if (idx >= orders.length) {
                          return SizedBox(
                            height: OrdersTokens.minTarget,
                            child: OutlinedButton(
                              onPressed: c.loadMore,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: OrdersTokens.blue,
                                side: const BorderSide(
                                  color: OrdersTokens.border,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    OrdersTokens.radius,
                                  ),
                                ),
                              ),
                              child: Text(
                                ordersStringsHi['loadMore']!,
                              ),
                            ),
                          );
                        }
                        final order = orders[idx];
                        final tagsKnown =
                            orders.every((o) => o.createdAt != null);
                        final tag = !tagsKnown
                            ? ''
                            : (_isFirstOrder(orders, order)
                                ? 'First order'
                                : 'Repeat');
                        return _OrderCard(
                          order: order,
                          historyTag: tag,
                          onTap: () => _openTracking(order),
                          onOpenBill: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => BillScreen(order: order),
                            ),
                          ),
                          onReorder: widget.onReorder == null
                              ? null
                              : () => widget.onReorder!(order),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.historyTag,
    required this.onTap,
    required this.onOpenBill,
    this.onReorder,
  });

  final Order order;

  /// '' = unknown (legacy rows) → no tag rendered, never guessed.
  final String historyTag;
  final VoidCallback onTap;
  final VoidCallback onOpenBill;
  final VoidCallback? onReorder;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(OrdersTokens.radius),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: OrdersTokens.white,
          border: Border.all(color: OrdersTokens.border),
          borderRadius: BorderRadius.circular(OrdersTokens.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${order.id}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: OrdersTokens.ink,
                    ),
                  ),
                ),
                if (order.isBulk)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: OrdersTokens.ink,
                      borderRadius: BorderRadius.circular(
                        OrdersTokens.radius,
                      ),
                    ),
                    child: const Text(
                      'Bulk',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: ShodashaTheme.bg,
                      ),
                    ),
                  ),
                _StatusChip(state: order.state),
              ],
            ),
            if (historyTag.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                historyTag,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: OrdersTokens.blue,
                ),
              ),
            ],
            if (order.itemSummary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                order.itemSummary,
                style: const TextStyle(
                  fontSize: 14,
                  color: OrdersTokens.muted,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _windowLabel(order),
                    style: const TextStyle(
                      fontSize: 13,
                      color: OrdersTokens.muted,
                    ),
                  ),
                ),
                Text(
                  formatRupees(order.totalPaise),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: OrdersTokens.ink,
                  ),
                ),
              ],
            ),
            if (order.refundPending) ...[
              const SizedBox(height: 6),
              Text(
                ordersStringsHi['refundPending']!,
                style: const TextStyle(
                  fontSize: 12,
                  color: OrdersTokens.blue,
                ),
              ),
            ],
            if (onReorder != null && order.canReorder) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onReorder,
                  icon: const Icon(Icons.repeat, size: 18),
                  label: const Text('Order again'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: OrdersTokens.blue,
                    side: const BorderSide(color: OrdersTokens.blue),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(OrdersTokens.radius),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _windowLabel(Order o) {
    String two(int n) => n.toString().padLeft(2, '0');
    final s = o.windowStart;
    final e = o.windowEnd ?? s.add(const Duration(minutes: 30));
    // F10: date rides with the time (same rule as the tracking card).
    return '${two(s.day)}/${two(s.month)} • ${two(s.hour)}:${two(s.minute)} - '
        '${two(e.hour)}:${two(e.minute)}';
  }
}

/// FLAT solid status chip: blueTint bg + blue text + dot (no shadows).
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.state});

  final OrderState state;

  @override
  Widget build(BuildContext context) => _StatusChip(state: state);
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});

  final OrderState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: OrdersTokens.blueTint,
        borderRadius: BorderRadius.circular(OrdersTokens.radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: OrdersTokens.blue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            state.name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: OrdersTokens.blue,
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => Container(
        height: 96,
        decoration: BoxDecoration(
          color: OrdersTokens.blueTint,
          borderRadius: BorderRadius.circular(OrdersTokens.radius),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.water_drop_outlined,
              size: 40,
              color: OrdersTokens.blue,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: OrdersTokens.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              style: const TextStyle(
                fontSize: 14,
                color: OrdersTokens.muted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 40,
              color: OrdersTokens.muted,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(fontSize: 15, color: OrdersTokens.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: OrdersTokens.minTarget,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ShodashaTheme.ink,
                  foregroundColor: OrdersTokens.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(OrdersTokens.radius),
                  ),
                ),
                child: Text(ordersStringsHi['retry']!),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: OrdersTokens.blueTint,
        borderRadius: BorderRadius.circular(OrdersTokens.radius),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off_outlined,
            size: 16,
            color: OrdersTokens.blue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ordersStringsHi['offlineTitle']!,
              style: const TextStyle(
                fontSize: 13,
                color: OrdersTokens.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
