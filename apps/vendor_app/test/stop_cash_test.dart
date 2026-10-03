// F2 cash post: one-tap "Cash jama karein" → money truth + badge reload.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/core/theme.dart';
import 'package:vendor_app/features/stops/stop_detail_screen.dart';
import 'package:vendor_app/features/stops/stops_controller.dart';

Map<String, dynamic> stopJson({String status = 'pending'}) => {
      'id': 's1',
      'route_id': 'r1',
      'order_id': 'o1',
      'customer_id': 'u1',
      'seq': 1,
      'fulls_exp': 2,
      'empties_exp': 1,
      'version': 2,
      'status': status,
      'total': 8600,
      'payment_mode': 'cod',
      'payment_status': 'unpaid',
      'customer_name': 'Sharma Ji',
      'address_text': '12 MG Road',
    };

void main() {
  testWidgets('cash button posts and shows jama notice', (tester) async {
    var cashCalls = 0;
    final mock = MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/vendor/stops/s1') && req.method == 'GET') {
        return http.Response(jsonEncode(stopJson()), 200);
      }
      if (p.endsWith('/vendor/stops/s1/cash')) {
        cashCalls++;
        final body = jsonDecode(req.body);
        expect(body['amount'], 8600);
        return http.Response(
          jsonEncode({
            'stop_id': 's1',
            'order_id': 'o1',
            'payment': {'id': 'pay1', 'amount': 8600, 'method': 'cod'},
            'order': {'id': 'o1', 'payment_status': 'paid_cash'},
            'ledger': {'dues': 0},
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
        home: StopDetailScreen(
          controller: StopsController(api: api),
          stopId: 's1',
          stopLabel: 'Stop 1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.textContaining('Cash jama karein'), findsOneWidget);
    await tester.tap(find.textContaining('Cash jama karein'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(cashCalls, 1);
    expect(find.text('Cash jama ho gaya'), findsOneWidget);
  });
}
