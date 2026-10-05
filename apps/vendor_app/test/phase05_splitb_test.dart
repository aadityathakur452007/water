// Phase 5 Split B — honest money predicates, pipeline labels, sync
// discard. Pure unit tests + controller tests, no backend.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/core/theme.dart';
import 'package:vendor_app/features/duty/duty_controller.dart';
import 'package:vendor_app/features/duty/duty_screen.dart';
import 'package:vendor_app/features/route/route_controller.dart';
import 'package:vendor_app/features/route/route_screen.dart';
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

  group('badge matrix (all 5 statuses render honestly)', () {
    Map<String, dynamic> stopJson(
      String id,
      String mode,
      String status,
      int paid,
    ) =>
        {
          'id': id,
          'seq': 1,
          'customer_name': 'C $id',
          'address': 'A',
          'fulls_exp': 2,
          'empties_exp': 1,
          'version': 1,
          'status': 'pending',
          'payment_mode': mode,
          'total': 20600,
          'payment_status': status,
          'paid_sum': paid,
        };

    testWidgets('route cards show remainder/link/paid, never full-twice',
        (tester) async {
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/vendor/routes/today')) {
          return http.Response(
              jsonEncode({
                'route': {'id': 'r1'},
                'stops': [
                  stopJson('s1', 'cod', 'unpaid', 0),
                  stopJson('s2', 'cod', 'partial_dues', 1000),
                  stopJson('s3', 'upi', 'link_sent', 0),
                  stopJson('s4', 'cod', 'paid_cash', 20600),
                  stopJson('s5', 'upi', 'paid_upi', 20600),
                ],
                'loading': {'take_fulls': 10, 'expect_empties': 5},
                'skip': [],
              }),
              200);
        }
        if (req.url.path.endsWith('/vendor/placed')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response('not found', 404);
      });
      final controller = RouteController(
          api: ApiClient(client: mock, deviceId: 't'));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: RouteScreen(controller: controller, onOpenStop: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      // Cards below the fold build lazily — scroll through the list first.
      await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(find.text('COD • Collect Rs 206'), findsOneWidget);
      expect(find.text('COD • Collect Rs 196 (baaki)'), findsOneWidget);
      expect(find.text('UPI • UPI link bheja, verify karein'), findsOneWidget);
      expect(find.text('COD • Paid'), findsOneWidget);
      expect(find.text('UPI • Paid'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('duty-off renders the repooled count', (tester) async {
      final mock = MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/vendor/profile')) {
          return http.Response(
              jsonEncode({'user_id': 'v1', 'on_duty': true}), 200);
        }
        if (p.endsWith('/vendor/routes/today')) {
          return http.Response(
              jsonEncode(
                  {'route': null, 'stops': [], 'loading': {}, 'skip': []}),
              200);
        }
        if (p.endsWith('/vendor/duty')) {
          return http.Response(
              jsonEncode(
                  {'duty_on': false, 'since': null, 'repooled': 2}),
              200);
        }
        return http.Response('not found', 404);
      });
      final controller =
          DutyController(api: ApiClient(client: mock, deviceId: 't'));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: DutyScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Haan, off karein'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 stops wapas pool mein'), findsOneWidget);
      controller.dispose();
    });
  });
}
