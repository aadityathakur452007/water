// 016 dashboard: TodayStrip totals (pure fold) + strip/money/ledger render.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/core/theme.dart';
import 'package:vendor_app/features/customers/customers_controller.dart';
import 'package:vendor_app/features/earnings/earnings_controller.dart';
import 'package:vendor_app/features/route/route_controller.dart';
import 'package:vendor_app/features/route/route_screen.dart';

RouteStop _stop({
  required String id,
  required String customerId,
  required String name,
  required int fulls,
  required String mode,
  required int total,
  required String payStatus,
  required String status,
}) =>
    RouteStop(
      id: id,
      seq: 1,
      customerName: name,
      customerId: customerId,
      address: 'addr',
      fullsExpected: fulls,
      emptiesExpected: 0,
      cashDuePaise: total,
      version: 1,
      status: status,
      paymentMode: mode,
      totalPaise: total,
      paymentStatus: payStatus,
    );

void main() {
  test('summarizeToday folds users/jars/UPI-COD split, paid excluded', () {
    final s = summarizeToday([
      _stop(id: 's1', customerId: 'u1', name: 'A', fulls: 2, mode: 'cod', total: 8600, payStatus: 'unpaid', status: 'pending'),
      _stop(id: 's2', customerId: 'u2', name: 'B', fulls: 1, mode: 'upi', total: 15000, payStatus: 'paid_upi', status: 'pending'),
      _stop(id: 's3', customerId: 'u1', name: 'A', fulls: 1, mode: 'cod', total: 2800, payStatus: 'unpaid', status: 'done'),
    ]);
    expect(s.users, 2); // distinct customerId, not stop count
    expect(s.jars, 4);
    expect(s.codCollect, 8600); // done stop leaves collect even though unpaid
    expect(s.upiCollect, 0); // paid stops add nothing to collect
    expect(s.done, 1);
    expect(s.total, 3);
  });

  testWidgets('dashboard strip + CTA + money + ledger render from server',
      (tester) async {
    final mock = MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/vendor/routes/today')) {
        return http.Response(
          jsonEncode({
            'route': {'id': 'r1'},
            'stops': [
              {
                'id': 's1', 'seq': 1, 'customer_id': 'u1',
                'customer_name': 'Sharma Ji', 'address': '12 MG Road',
                'fulls_exp': 2, 'empties_exp': 1, 'total': 8600,
                'payment_mode': 'cod', 'payment_status': 'unpaid',
                'version': 1, 'status': 'pending',
              },
            ],
            'skip': [],
            'loading': {'take_fulls': 2, 'expect_empties': 1},
          }),
          200,
        );
      }
      if (p.endsWith('/vendor/earnings')) {
        return http.Response(
          jsonEncode({
            'shift': '2026-10-03', 'stops_done': 1, 'cash_total': 4600,
            'upi_total': 4000, 'flagged_stops': 0, 'flagged_hold': 0,
          }),
          200,
        );
      }
      if (p.endsWith('/vendor/customers')) {
        return http.Response(
          jsonEncode({
            'date': '2026-10-03',
            'customers': [
              {
                'customer_id': 'u1', 'customer_name': 'Sharma Ji',
                'stops': [], 'fulls_exp': 2, 'empties_exp': 1, 'done': 0,
                'held': 2, 'dues': 8600,
              },
            ],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final api = ApiClient(client: mock, deviceId: 'test-device');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: RouteScreen(
          controller: RouteController(api: api),
          earnings: EarningsController(api: api),
          customers: CustomersController(api: api),
          onOpenStop: (_) {},
          onOpenSync: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    // §3(a): banner strip with split (paid-excluded, computed truth).
    expect(find.text('Aaj ka hisaab'), findsOneWidget);
    expect(find.textContaining('1 grahak · 2 jars'), findsOneWidget);
    expect(find.textContaining('Collect Rs 86 (UPI Rs 0'), findsOneWidget);
    expect(find.textContaining('COD Rs 86'), findsOneWidget);
    // One CTA: first pending stop → Triple (no sync backlog).
    expect(find.textContaining('Triple:'), findsOneWidget);
    // §3(c): inline display-only money from earnings.
    expect(find.textContaining('Jama Rs 86'), findsOneWidget);
    // §3(d): ledger row only for nonzero held/dues.
    expect(find.textContaining('2 held'), findsOneWidget);
    expect(find.textContaining('Rs 86 baaki'), findsOneWidget);
  });
}
