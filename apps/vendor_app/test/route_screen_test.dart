// Route screen renders server-driven stops (MockClient, no backend).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/core/theme.dart';
import 'package:vendor_app/features/route/route_controller.dart';
import 'package:vendor_app/features/route/route_screen.dart';

void main() {
  testWidgets('route sheet shows loading header + stop cards',
      (tester) async {
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/vendor/routes/today')) {
        return http.Response(
          jsonEncode({
            'route': {'id': 'r1'},
            'stops': [
              {
                'id': 's1',
                'seq': 1,
                'customer_name': 'Sharma Ji',
                'address': '12 MG Road',
                'fulls_exp': 2,
                'empties_exp': 1,
                'cash_due': 8600,
                'version': 1,
                'status': 'pending',
              },
            ],
            'skip': [],
            'loading': {'take_fulls': 40, 'expect_empties': 35},
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final api = ApiClient(client: mock, deviceId: 'test-device');
    final controller = RouteController(api: api);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: RouteScreen(controller: controller, onOpenStop: (_) {}),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.textContaining('40 fulls lein'), findsOneWidget);
    expect(find.text('Sharma Ji'), findsOneWidget);
    expect(find.textContaining('Rs 86'), findsOneWidget);
  });
}
