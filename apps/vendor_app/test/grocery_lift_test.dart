// 011-grocery-verify — runtime proof the vendor lift is actually rendered:
// header rows with counts, bordered tile rows, and the hand-rolled cascade
// (CascadeScope + CascadeItem, zero flutter_animate). MockClient, no backend.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/core/cascade.dart';
import 'package:vendor_app/core/theme.dart';
import 'package:vendor_app/features/customers/customers_controller.dart';
import 'package:vendor_app/features/customers/customers_screen.dart';
import 'package:vendor_app/features/route/route_controller.dart';
import 'package:vendor_app/features/route/route_screen.dart';

MockClient _mock() => MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/vendor/routes/today')) {
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
              'skip': [
                {
                  'id': 's9',
                  'seq': 9,
                  'customer_name': 'Paused Ji',
                  'address': '',
                  'fulls_exp': 1,
                  'empties_exp': 0,
                  'cash_due': 0,
                  'version': 1,
                  'status': 'paused',
                },
              ],
              'loading': {'take_fulls': 40, 'expect_empties': 35},
            }),
            200);
      }
      if (p.endsWith('/vendor/customers')) {
        return http.Response(
            jsonEncode({
              'date': '2026-10-02',
              'customers': [
                {
                  'customer_id': 'u1',
                  'customer_name': 'Cust One',
                  'customer_phone': '+912222222222',
                  'stops': [
                    {'stop_id': 's1', 'seq': 0, 'status': 'done', 'order_id': 'o1'},
                  ],
                  'fulls_exp': 3,
                  'empties_exp': 1,
                  'done': 1,
                }
              ]
            }),
            200);
      }
      return http.Response('not found', 404);
    });

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  testWidgets('route renders lifted headers + cards + cascade',
      (tester) async {
    final api = ApiClient(client: _mock(), deviceId: 't');
    final controller = RouteController(api: api);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: RouteScreen(controller: controller, onOpenStop: (_) {}),
      ),
    );
    await _settle(tester);

    // Section-header rows with live counts.
    expect(find.text('Loading sheet'), findsOneWidget);
    expect(find.text('SKIP (pause/late)'), findsOneWidget);
    // Stop cards (active + greyed skip).
    expect(find.text('Sharma Ji'), findsOneWidget);
    expect(find.text('Paused Ji'), findsOneWidget);
    // Hand-rolled cascade wraps every row.
    expect(find.byType(CascadeScope), findsOneWidget);
    expect(find.byType(CascadeItem), findsNWidgets(2));
  });

  testWidgets('customers render tile rows + cascade', (tester) async {
    final api = ApiClient(client: _mock(), deviceId: 't');
    final controller = CustomersController(api: api);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: CustomersScreen(controller: controller),
      ),
    );
    await _settle(tester);

    // Tile row: name + phone + totals + chevron affordance.
    expect(find.text('Cust One'), findsOneWidget);
    expect(find.text('+912222222222'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.byType(CascadeScope), findsOneWidget);
    expect(find.byType(CascadeItem), findsOneWidget);
  });
}
