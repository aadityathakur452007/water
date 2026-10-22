// Phase B (state audit P1) regression tests.
//
// Plugin-free: money formatting, UPI validation, orders load-more/offline
// truth and rating outcomes. No device, no network.
// Run: flutter test test/phase_b_states_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/core/money.dart';
import 'package:shodasha_app/features/orders/orders_controller.dart';
import 'package:shodasha_app/features/returns/return_sheet.dart';

Order _order(String id) => Order(
  id: id,
  state: OrderState.placed,
  windowStart: DateTime(2026, 10, 22, 9),
  windowEnd: DateTime(2026, 10, 22, 9, 30),
  itemSummary: '2 jars',
  addressLabel: 'Sector 21',
  totalPaise: 5600,
);

/// Page-aware fake with controllable failures/delays.
class _PagedRepo implements OrdersRepository {
  _PagedRepo(this.pages);

  final List<OrdersPage> pages;
  bool failMore = false;
  bool failAll = false;
  int fetchCalls = 0;
  Completer<OrdersPage>? gate;

  @override
  Future<OrdersPage> fetchOrders({String? cursor}) async {
    fetchCalls++;
    if (failAll || (failMore && cursor != null)) {
      throw ApiException(code: 'NETWORK', message: 'offline', statusCode: 0);
    }
    if (cursor == null) return pages.first;
    final g = gate;
    if (g != null) await g.future;
    return pages.last;
  }

  @override
  Future<Order> fetchOrder(String id) async =>
      pages.expand((p) => p.orders).firstWhere((o) => o.id == id);

  @override
  Future<Order> cancelOrder(String id, String reasonCode) async =>
      fetchOrder(id);

  @override
  Future<Order> rescheduleOrder(String id, DateTime windowStart) async =>
      fetchOrder(id);

  @override
  Future<Order> submitRating(String id, int stars) async => fetchOrder(id);
}

class _RatingFailRepo extends StubOrdersRepository {
  _RatingFailRepo(super.seed, {this.alreadyRated = false});

  final bool alreadyRated;

  @override
  Future<Order> submitRating(String id, int stars) async {
    if (alreadyRated) {
      throw ApiException(
        code: 'ALREADY_RATED',
        message: 'Order already rated.',
        statusCode: 409,
      );
    }
    throw ApiException(code: 'NETWORK', message: 'offline', statusCode: 0);
  }
}

void main() {
  group('formatInr (shared money display)', () {
    test('whole rupees keep no decimals', () {
      expect(formatInr(0), '₹0');
      expect(formatInr(5600), '₹56');
      expect(formatInr(-5600), '-₹56');
    });

    test('paise show two decimals', () {
      expect(formatInr(5650), '₹56.50');
      expect(formatInr(5), '₹0.05');
      expect(formatInr(100005), '₹1000.05');
    });

    test('formatRupees delegates to the shared formatter', () {
      expect(formatRupees(5650), formatInr(5650));
    });
  });

  group('isValidUpi (return refund VPA)', () {
    test('accepts common UPI ids', () {
      expect(isValidUpi('name@bank'), isTrue);
      expect(isValidUpi('9876543210@upi'), isTrue);
      expect(isValidUpi('a.b-c_d@okhdfcbank'), isTrue);
      expect(isValidUpi('  name@ybl  '), isTrue);
    });

    test('rejects empty / malformed ids', () {
      expect(isValidUpi(''), isFalse);
      expect(isValidUpi('name'), isFalse);
      expect(isValidUpi('@bank'), isFalse);
      expect(isValidUpi('name@'), isFalse);
      expect(isValidUpi('name @bank'), isFalse);
      expect(isValidUpi('a@b'), isFalse);
    });
  });

  group('orders loadMore', () {
    test('dedupes overlapping cursor pages', () async {
      final repo = _PagedRepo([
        OrdersPage(orders: [_order('o1'), _order('o2')], nextCursor: 'c1'),
        OrdersPage(orders: [_order('o2'), _order('o3')]),
      ]);
      final c = OrdersController(repo: repo);
      await c.load();
      expect(c.totalCount, 2);
      await c.loadMore();
      expect(c.totalCount, 3, reason: 'o2 must not be rendered twice');
      expect(c.loadMoreFailed, isFalse);
      c.dispose();
    });

    test('in-flight guard prevents a double fetch', () async {
      final repo = _PagedRepo([
        OrdersPage(orders: [_order('o1')], nextCursor: 'c1'),
        OrdersPage(orders: [_order('o2')]),
      ]);
      final c = OrdersController(repo: repo);
      await c.load();
      final gate = Completer<OrdersPage>();
      repo.gate = gate;
      final first = c.loadMore();
      expect(c.loadingMore, isTrue);
      await c.loadMore(); // must no-op while the first is in flight
      expect(repo.fetchCalls, 2, reason: 'one list load + one page load');
      gate.complete(repo.pages.last);
      await first;
      expect(c.totalCount, 2);
      expect(c.loadingMore, isFalse);
      c.dispose();
    });

    test('failure is visible and retry clears it', () async {
      final repo = _PagedRepo([
        OrdersPage(orders: [_order('o1')], nextCursor: 'c1'),
        OrdersPage(orders: [_order('o2')]),
      ])..failMore = true;
      final c = OrdersController(repo: repo);
      await c.load();
      await c.loadMore();
      expect(c.loadMoreFailed, isTrue);
      expect(c.loadingMore, isFalse);
      expect(c.totalCount, 1);
      expect(c.hasMore, isTrue);
      repo.failMore = false;
      await c.retryLoadMore();
      expect(c.loadMoreFailed, isFalse);
      expect(c.totalCount, 2);
      c.dispose();
    });
  });

  group('orders offline truth', () {
    test('network refresh keeps rows and raises the banner', () async {
      final repo = _PagedRepo([
        OrdersPage(orders: [_order('o1')]),
      ]);
      final c = OrdersController(repo: repo);
      await c.load();
      expect(c.status, OrdersListStatus.loaded);
      expect(c.isOffline, isFalse);
      repo.failAll = true;
      await c.refresh();
      expect(c.status, OrdersListStatus.loaded);
      expect(c.isOffline, isTrue);
      expect(c.totalCount, 1);
      repo.failAll = false;
      await c.load();
      expect(c.isOffline, isFalse);
      c.dispose();
    });
  });

  group('rating outcomes', () {
    test('network failure is failed, not already-rated', () async {
      final repo = _RatingFailRepo([_order('o1')]);
      final c = OrdersController(repo: repo);
      await c.load();
      expect(await c.rate('o1', 5), RateResult.failed);
      c.dispose();
    });

    test('server 409 maps to alreadyRated', () async {
      final repo = _RatingFailRepo([_order('o1')], alreadyRated: true);
      final c = OrdersController(repo: repo);
      await c.load();
      expect(await c.rate('o1', 5), RateResult.alreadyRated);
      c.dispose();
    });
  });
}
