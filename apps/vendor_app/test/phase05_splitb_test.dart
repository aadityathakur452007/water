// Phase 5 Split B — honest money predicates, pipeline labels, sync
// discard. Pure unit tests + controller tests, no backend.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/features/route/route_controller.dart';
import 'package:vendor_app/features/stops/stops_controller.dart';
import 'package:vendor_app/features/sync/sync_controller.dart';

RouteStop _stop(String status, {int total = 20600, int paid = 0}) =>
    RouteStop.fromJson({
      'id': 's1',
      'seq': 1,
      'customer_name': 'C',
      'address': 'A',
      'fulls_exp': 2,
      'empties_exp': 1,
      'version': 1,
      'status': 'pending',
      'payment_mode': 'cod',
      'total': total,
      'payment_status': status,
      'paid_sum': paid,
    });

void main() {
  group('payment predicates (all 5 statuses)', () {
    test('unpaid collects the full total', () {
      final s = _stop('unpaid');
      expect(s.isPaid, isFalse);
      expect(s.isPartial, isFalse);
      expect(s.isLinkSent, isFalse);
      expect(s.remainingPaise, 20600);
    });

    test('partial collects the remainder, never the full total', () {
      final s = _stop('partial_dues', paid: 1000);
      expect(s.isPaid, isFalse);
      expect(s.isPartial, isTrue);
      expect(s.remainingPaise, 19600);
    });

    test('partial beyond total clamps to zero', () {
      final s = _stop('partial_dues', total: 1000, paid: 5000);
      expect(s.remainingPaise, 0);
    });

    test('link_sent demands nothing (webhook pending)', () {
      final s = _stop('link_sent');
      expect(s.isLinkSent, isTrue);
      expect(s.remainingPaise, 0);
    });

    test('paid demands nothing', () {
      for (final st in ['paid_upi', 'paid_cash']) {
        expect(_stop(st).remainingPaise, 0);
      }
    });

    test('today fold: partial adds remainder, link/paid add zero', () {
      final stops = [
        _stop('unpaid'),
        _stop('partial_dues', paid: 1000),
        _stop('link_sent'),
        _stop('paid_cash'),
      ];
      final sum = summarizeToday(stops);
      expect(sum.codCollect, 20600 + 19600);
      expect(sum.collect, 20600 + 19600);
    });
  });

  group('pipeline labels', () {
    test('mapped states carry meaning, unknown hides', () {
      expect(orderStateLabelHi('dispatched'), contains('Raste'));
      expect(orderStateLabelHi('assigned'), isNotEmpty);
      expect(orderStateLabelHi('delivered'), isNotEmpty);
      expect(orderStateLabelHi('placed'), isNotEmpty);
      expect(orderStateLabelHi('whatever_server_sends'), isEmpty);
      expect(orderStateLabelHi(''), isEmpty);
    });
  });

  group('sync discard', () {
    test('stuck reject drops its queue entries, rest stays', () async {
      SharedPreferences.setMockInitialValues({});
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/vendor/sync')) {
          return http.Response(
              jsonEncode({
                'applied': [],
                'replayed': [],
                'rejected': [
                  {'stop_id': 's1', 'code': 'STALE_STOP', 'message': 'stale'}
                ],
              }),
              200);
        }
        return http.Response('not found', 404);
      });
      final c = SyncController(
          api: ApiClient(client: mock, deviceId: 't'));
      await c.load();
      await c.enqueue(stopId: 's1', triple: {'version': 1});
      await c.enqueue(stopId: 's2', triple: {'version': 1});
      await c.syncNow();
      expect(c.rejected, hasLength(1));
      await c.discardRejected('s1');
      expect(c.rejected, isEmpty);
      expect(c.queue.map((q) => q.stopId), ['s2']);
      c.dispose();
    });
  });
}
