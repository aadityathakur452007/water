// Live orders mapping proof (015): ApiBackedOrdersRepository over a
// MockClient serving real wire shapes (OrderOut / OrderDetailOut /
// CancelOut per workers/api schemas/orders.py + ratings.py).
// Pure unit tests — no tracking timer started, no pump needed.
// Run: flutter test test/live_orders_mapping_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/features/orders/orders_controller.dart';

Map<String, dynamic> orderJson({
  String id = 'o1',
  String state = 'dispatched',
  String paymentMode = 'upi',
  String paymentStatus = 'paid_upi',
  List<Map<String, dynamic>>? items,
  String windowEnd = '2026-10-04T08:30:00Z',
}) {
  return {
    'id': id,
    'user_id': 'u1',
    'address_id': 'a1',
    'items': items ??
        [
          {'sku': 'refill', 'qty': 2},
          {'sku': 'container', 'qty': 1},
        ],
    'n': 3,
    'e': 1,
    'water_bill': 5600,
    'deposit_due': 15000,
    'cap_charge': 0,
    'total': 20600,
    'payment_mode': paymentMode,
    'payment_status': paymentStatus,
    'state': state,
    'window_start': '2026-10-04T08:00:00Z',
    'window_end': windowEnd,
    'quote_hash': 'h',
    'quote_rate_version': 'v3',
    'created_at': '2026-10-03T10:00:00Z',
  };
}

Map<String, dynamic> detailJson() => {
      ...orderJson(),
      'tracker': {
        'steps': ['placed', 'packed', 'dispatched', 'delivered'],
        'current': 'dispatched',
      },
      'rider': {'name': 'Raju', 'call': '+919000000002'},
      'bill': {
        'water_bill': 5600,
        'deposit_due': 15000,
        'cap_charge': 0,
        'total': 20600,
        'payment_status': 'paid_upi',
      },
      'events': [],
    };

/// Mock backend with a request log. Routes on method + path tail.
MockClient backend(List<http.BaseRequest> log, {bool failList = false}) {
  return MockClient((req) async {
    log.add(req);
    final path = req.url.path;
    if (req.method == 'POST' && path.endsWith('/cancel')) {
      return http.Response(
        jsonEncode({
          'order_id': 'o1',
          'state': 'cancelled',
          'bill_total': 0,
          'deposit_reversed': 15000,
          'refund': null,
        }),
        200,
      );
    }
    if (req.method == 'POST' && path.endsWith('/reschedule')) {
      return http.Response(jsonEncode(orderJson(state: 'placed')), 200);
    }
    if (req.method == 'POST' && path.endsWith('/rating')) {
      return http.Response(
        jsonEncode(
          {'order_id': 'o1', 'stars': 5, 'complaint_shortcut': false},
        ),
        201,
      );
    }
    if (req.method == 'GET' && path.endsWith('/orders')) {
      if (failList) throw http.ClientException('offline');
      final cursor = req.url.queryParameters['cursor'];
      if (cursor == 'CUR2') {
        return http.Response(
          jsonEncode({'data': [], 'next_cursor': null}),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'data': [
            orderJson(),
            orderJson(
              id: 'o2',
              state: 'flying',
              paymentMode: 'cod',
              paymentStatus: 'unpaid',
            ),
          ],
          'next_cursor': 'CUR2',
        }),
        200,
      );
    }
    if (req.method == 'GET' && path.contains('/orders/')) {
      return http.Response(jsonEncode(detailJson()), 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  group('ApiBackedOrdersRepository mapping', () {
    test('fetchOrders maps state/payment/bill/items/cursor', () async {
      final log = <http.BaseRequest>[];
      final repo = ApiBackedOrdersRepository(
        ApiClient(client: backend(log), deviceId: 't'),
      );
      final page = await repo.fetchOrders();

      expect(page.nextCursor, 'CUR2');
      expect(page.orders.length, 2);

      final o = page.orders.first;
      expect(o.id, 'o1');
      expect(o.state, OrderState.dispatched);
      expect(o.paymentMode, 'upi');
      expect(o.paymentStatus, 'paid_upi');
      expect(o.isPaid, isTrue);
      expect(o.itemSummary, '2 refill + 1 container');
      expect(o.refillQty, 2);
      expect(o.containerQty, 1);
      expect(o.canReorder, isTrue);
      expect(o.waterBillPaise, 5600);
      expect(o.depositDuePaise, 15000);
      expect(o.capChargePaise, 0);
      expect(o.totalPaise, 20600);
      // Server bill has no prev/payments keys → honest zeros.
      expect(o.prevDuesPaise, 0);
      expect(o.paymentsPaise, 0);
      expect(o.windowEnd?.hour, 8);
      expect(o.windowEnd?.minute, 30);
      expect(o.createdAt, isNotNull);

      // Unknown state string never crashes → placed.
      expect(page.orders[1].state, OrderState.placed);
      expect(page.orders[1].isPaid, isFalse);
    });

    test('cursor passthrough: second page sends cursor, ends list', () async {
      final log = <http.BaseRequest>[];
      final repo = ApiBackedOrdersRepository(
        ApiClient(client: backend(log), deviceId: 't'),
      );
      final page = await repo.fetchOrders(cursor: 'CUR2');
      expect(page.orders, isEmpty);
      expect(page.nextCursor, isNull);
      final listReq = log.single;
      expect(listReq.url.queryParameters['cursor'], 'CUR2');
    });

    test('fetchOrder maps rider {name,call} + bill', () async {
      final log = <http.BaseRequest>[];
      final repo = ApiBackedOrdersRepository(
        ApiClient(client: backend(log), deviceId: 't'),
      );
      final o = await repo.fetchOrder('o1');
      expect(o.riderName, 'Raju');
      expect(o.riderPhone, '+919000000002');
      expect(o.totalPaise, 20600);
      expect(o.paymentMode, 'upi');
    });

    test('cancel posts reason + Idempotency-Key, then re-reads', () async {
      final log = <http.BaseRequest>[];
      final repo = ApiBackedOrdersRepository(
        ApiClient(client: backend(log), deviceId: 't'),
      );
      final o = await repo.cancelOrder('o1', 'changed_mind');
      expect(log.length, 2);
      final post = log.first;
      expect(post.method, 'POST');
      expect(post.url.path.endsWith('/cancel'), isTrue);
      expect(post.headers['Idempotency-Key'], isNotEmpty);
      final body = jsonDecode(
        (post as http.Request).body,
      ) as Map<String, dynamic>;
      expect(body['reason'], 'changed_mind');
      expect(log[1].method, 'GET');
      expect(o.id, 'o1');
    });

    test('reschedule posts window_start ISO', () async {
      final log = <http.BaseRequest>[];
      final repo = ApiBackedOrdersRepository(
        ApiClient(client: backend(log), deviceId: 't'),
      );
      final start = DateTime(2026, 10, 5, 9, 0);
      final o = await repo.rescheduleOrder('o1', start);
      expect(log.length, 1);
      final body = jsonDecode(
        (log.single as http.Request).body,
      ) as Map<String, dynamic>;
      expect(body['window_start'], start.toIso8601String());
      expect(o.state, OrderState.placed);
    });

    test('submitRating posts stars, returns rated order (qtys kept)',
        () async {
      final log = <http.BaseRequest>[];
      final repo = ApiBackedOrdersRepository(
        ApiClient(client: backend(log), deviceId: 't'),
      );
      final o = await repo.submitRating('o1', 5);
      final body = jsonDecode(
        (log.first as http.Request).body,
      ) as Map<String, dynamic>;
      expect(body['stars'], 5);
      expect(o.rated, isTrue);
      expect(o.stars, 5);
      expect(o.refillQty, 2);
      expect(o.containerQty, 1);
    });

    test('NETWORK ApiException rethrown (controller owns offline states)',
        () async {
      final log = <http.BaseRequest>[];
      final repo = ApiBackedOrdersRepository(
        ApiClient(client: backend(log, failList: true), deviceId: 't'),
      );
      expect(
        () => repo.fetchOrders(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'NETWORK'),
        ),
      );
    });
  });
}
