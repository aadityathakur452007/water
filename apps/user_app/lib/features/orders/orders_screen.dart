// S5 — Orders list screen (search + cursor list + skeleton + empty +
// error/offline rows). Contract §4.4 + flows 3/5.
//
// Ported from apps/user_app_legacy_flutter F4; the donor order-card grammar
// is kept as the visual language: white card on the slate ground, hairline
// border + 3% soft shadow, 800-weight order id in brand teal, tinted status
// pill, 12px icon meta rows, 900-weight server total.
//
// States.md covered: loading (skeleton) / empty / no-results / error /
// offline (cached rows stay visible) / refreshing / searching / action busy.
//
// Cross-feature doors are nullable callbacks (no feature-folder imports):
//   onReorder       → booking sheet with the order's SKU mix (S4/S3)
//   onOpenPayments  → payments history (S7)
//   onSupport       → complaints/support screen (S8)
// Strings + navigation are frozen (the ported tests assert exact copy).

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'orders_controller.dart';
import 'tracking_screen.dart';

/// Search + cursor-paged order list (repeat-first: reorder buttons).
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({
    super.key,
    required this.controller,
    this.isAuthenticated,
    this.onReorder,
    this.onOpenPayments,
    this.onSupport,
  });

  final OrdersController controller;
  final bool Function()? isAuthenticated;

  /// One-tap repeat: fills the booking lines from [order], then opens
  /// checkout (caller). Null = reorder hidden (guest wiring pending).
  final ValueChanged<Order>? onReorder;

  /// Payments history entry (S7). Hidden when null — never a dead icon.
  final VoidCallback? onOpenPayments;

  /// Complaints/support entry (S8), forwarded to the rating sheet shortcut.
  final VoidCallback? onSupport;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
    final authed = widget.isAuthenticated?.call() ?? true;
    if (authed && widget.controller.status == OrdersListStatus.initial) {
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
          onSupport: widget.onSupport,
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
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(
        backgroundColor: ShodashaTheme.bg,
        elevation: 0,
        title: Text(
          ordersStringsHi['ordersTitle']!,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: ShodashaTheme.ink,
          ),
        ),
        actions: [
          if (widget.onOpenPayments != null)
            IconButton(
              tooltip: 'Mere Payments / Hisaab',
              icon: const Icon(
                Icons.receipt_long_outlined,
                color: ShodashaTheme.ink,
              ),
              onPressed: widget.onOpenPayments,
            ),
        ],
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
                style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
                decoration: InputDecoration(
                  labelText: ordersStringsHi['searchHint'],
                  hintText: ordersStringsHi['searchHint'],
                  hintStyle: const TextStyle(color: ShodashaTheme.muted),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: ShodashaTheme.muted,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                    borderSide: const BorderSide(color: ShodashaTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                    borderSide: const BorderSide(color: ShodashaTheme.teal),
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
                  if (c.status == OrdersListStatus.error && c.totalCount == 0) {
                    return _ErrorRow(
                      message: c.errorMessage ?? ordersStringsHi['errorTitle']!,
                      onRetry: c.load,
                    );
                  }
                  final orders = c.filteredOrders;
                  if (orders.isEmpty && c.query.trim().isNotEmpty) {
                    return _EmptyState(
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
                    color: ShodashaTheme.teal,
                    onRefresh: c.refresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount:
                          orders.length +
                          ((c.hasMore || c.loadMoreFailed) ? 1 : 0) +
                          (c.isOffline ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (c.isOffline && i == 0) {
                          return const _OfflineBanner();
                        }
                        final idx = c.isOffline ? i - 1 : i;
                        if (idx >= orders.length) {
                          if (c.loadMoreFailed) {
                            return Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    ordersStringsHi['loadMoreFailed']!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: ShodashaTheme.muted,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: c.retryLoadMore,
                                  child: Text(ordersStringsHi['retry']!),
                                ),
                              ],
                            );
                          }
                          return SizedBox(
                            height: ShodashaTheme.minTarget,
                            child: OutlinedButton(
                              onPressed: c.loadingMore ? null : c.loadMore,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: ShodashaTheme.teal,
                                side: const BorderSide(
                                  color: ShodashaTheme.border,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    ShodashaTheme.radius,
                                  ),
                                ),
                              ),
                              child: c.loadingMore
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: ShodashaTheme.teal,
                                      ),
                                    )
                                  : Text(ordersStringsHi['loadMore']!),
                            ),
                          );
                        }
                        final order = orders[idx];
                        final tagsKnown = orders.every(
                          (o) => o.createdAt != null,
                        );
                        final tag = !tagsKnown
                            ? ''
                            : (_isFirstOrder(orders, order)
                                  ? 'First order'
                                  : 'Repeat');
                        return _OrderCard(
                          order: order,
                          historyTag: tag,
                          onTap: () => _openTracking(order),
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
    this.onReorder,
  });

  final Order order;

  /// '' = unknown (legacy rows) → no tag rendered, never guessed.
  final String historyTag;
  final VoidCallback onTap;
  final VoidCallback? onReorder;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      onTap: onTap,
      child: Container(
        // Donor order-card craft — white surface on the slate ground,
        // hairline border + 3% soft shadow. Flat, no gradients.
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ShodashaTheme.surface,
          border: Border.all(color: ShodashaTheme.border),
          borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
          boxShadow: [
            BoxShadow(
              color: ShodashaTheme.ink.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Donor meta head: 800-weight id in the brand color + status pill.
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${order.id}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: ShodashaTheme.teal,
                    ),
                  ),
                ),
                if (order.isBulk) ...[
                  const SizedBox(width: 6),
                  const _BulkPill(),
                  const SizedBox(width: 6),
                ],
                _StatusChip(state: order.state),
              ],
            ),
            if (historyTag.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                historyTag,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: ShodashaTheme.muted,
                ),
              ),
            ],
            // Jar mix (refill + container) — honest server summary.
            if (order.itemSummary.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                order.itemSummary,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: ShodashaTheme.ink,
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Donor meta rows: 12px token-muted info with 14px icons.
            Row(
              children: [
                const Icon(
                  Icons.schedule,
                  size: 14,
                  color: ShodashaTheme.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  _windowLabel(order),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ShodashaTheme.muted,
                  ),
                ),
                const Spacer(),
                Text(
                  formatRupees(order.totalPaise),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: ShodashaTheme.ink,
                  ),
                ),
              ],
            ),
            if (order.addressLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 14,
                    color: ShodashaTheme.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.addressLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: ShodashaTheme.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (order.refundPending) ...[
              const SizedBox(height: 6),
              Text(
                ordersStringsHi['refundPending']!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ShodashaTheme.muted,
                ),
              ),
            ],
            if (onReorder != null && order.canReorder) ...[
              const SizedBox(height: 12),
              // Money CTA → token green (locked). 48dp target.
              SizedBox(
                width: double.infinity,
                height: ShodashaTheme.minTarget,
                child: ElevatedButton.icon(
                  onPressed: onReorder,
                  icon: const Icon(Icons.repeat, size: 18),
                  label: const Text(
                    'Reorder',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ShodashaTheme.green,
                    foregroundColor: ShodashaTheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
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

/// Donor-style status pill: tint chip + 800-weight micro label (no dot,
/// no shadows). Maps OUR state set only — teal for in-flight, neutral slate
/// for delivered, danger for failed/rejected (never a fake status).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});

  final OrderState state;

  (Color bg, Color fg) _tone(OrderState s) {
    switch (s) {
      case OrderState.placed:
      case OrderState.accepted:
      case OrderState.picked:
      case OrderState.packed:
      case OrderState.assigned:
      case OrderState.dispatched:
        return (ShodashaTheme.tealTint, ShodashaTheme.teal);
      case OrderState.delivered:
        return (ShodashaTheme.bg, ShodashaTheme.muted);
      case OrderState.failed:
      case OrderState.rejected:
        return (ShodashaTheme.bg, ShodashaTheme.danger);
      case OrderState.cancelled:
        return (ShodashaTheme.bg, ShodashaTheme.muted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _tone(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ShodashaTheme.radius / 2),
      ),
      child: Text(
        state.name,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: fg,
        ),
      ),
    );
  }
}

/// Bulk nudge (dark lip — informational, not a status).
class _BulkPill extends StatelessWidget {
  const _BulkPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: ShodashaTheme.ink,
        borderRadius: BorderRadius.circular(ShodashaTheme.radius / 2),
      ),
      child: Text(
        'Bulk',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: ShodashaTheme.bg,
        ),
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
          color: ShodashaTheme.tealTint,
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
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
              color: ShodashaTheme.teal,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ShodashaTheme.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              style: const TextStyle(fontSize: 14, color: ShodashaTheme.muted),
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
              color: ShodashaTheme.muted,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(fontSize: 15, color: ShodashaTheme.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: ShodashaTheme.minTarget,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ShodashaTheme.ink,
                  foregroundColor: ShodashaTheme.bg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
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
        color: ShodashaTheme.tealTint,
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off_outlined,
            size: 16,
            color: ShodashaTheme.teal,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ordersStringsHi['offlineTitle']!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ShodashaTheme.teal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
