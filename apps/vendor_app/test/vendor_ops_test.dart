import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/core/theme.dart';
import 'package:vendor_app/features/customers/customers_controller.dart';
import 'package:vendor_app/features/customers/customers_screen.dart';
import 'package:vendor_app/features/earnings/earnings_controller.dart';
import 'package:vendor_app/features/earnings/earnings_screen.dart';
import 'package:vendor_app/features/inventory/inventory_screen.dart';
import 'package:vendor_app/features/route/route_controller.dart';
import 'package:vendor_app/features/support/support_controller.dart';
import 'package:vendor_app/features/support/support_screen.dart';
import 'package:vendor_app/shared/ui/app_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomersScreen unslop verification', () {
    testWidgets('error state renders AppButton retry CTA', (tester) async {
      final mock = MockClient((req) async => http.Response('{"error": "fail"}', 400));
      final api = ApiClient(client: mock, deviceId: 'test-device');
      final controller = CustomersController(api: api);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: CustomersScreen(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      final retryFinder = find.widgetWithText(AppButton, 'Dobara try karein');
      expect(retryFinder, findsOneWidget);
      final button = tester.widget<AppButton>(retryFinder);
      expect(button.kind, AppButtonKind.primary);
      expect(button.expand, isFalse);

      controller.dispose();
    });

    testWidgets('loaded customer tap opens detail sheet with radiusSheet', (tester) async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'customers': [
              {
                'customer_id': 'c-1',
                'customer_name': 'Ramesh Kumar',
                'customer_phone': '9876543210',
                'stops': [
                  {'stop_id': 's1', 'seq': 1, 'status': 'completed'},
                  {'stop_id': 's2', 'seq': 2, 'status': 'pending'},
                ],
                'fulls_exp': 4,
                'empties_exp': 3,
                'done': 1,
                'held': 2,
                'dues': 0,
              }
            ]
          }),
          200,
        );
      });
      final api = ApiClient(client: mock, deviceId: 'test-device');
      final controller = CustomersController(api: api);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: CustomersScreen(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.text('Ramesh Kumar'), findsOneWidget);
      await tester.tap(find.text('Ramesh Kumar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify bottom sheet modal is open with customer stop details
      expect(find.text('Stop 1'), findsOneWidget);
      expect(find.text('Stop 2'), findsOneWidget);

      controller.dispose();
    });
  });

  group('InventoryScreen unslop verification', () {
    testWidgets('error state renders AppButton retry CTA', (tester) async {
      final mock = MockClient((req) async => http.Response('{"error": "fail"}', 400));
      final api = ApiClient(client: mock, deviceId: 'test-device');
      final route = RouteController(api: api);
      await route.load();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: InventoryScreen(route: route),
        ),
      );
      await tester.pump();

      final retryFinder = find.widgetWithText(AppButton, 'Dobara try karein');
      expect(retryFinder, findsOneWidget);
      final button = tester.widget<AppButton>(retryFinder);
      expect(button.kind, AppButtonKind.primary);
      expect(button.expand, isFalse);

      route.dispose();
    });

    testWidgets('loaded state renders stock metrics', (tester) async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'route': {'id': 'r1'},
            'stops': [
              {
                'id': 's1',
                'seq': 1,
                'status': 'done',
                'fulls_exp': 2,
                'empties_exp': 2,
              },
            ],
            'summary': {'take_fulls': 10, 'expect_empties': 8},
          }),
          200,
        );
      });
      final api = ApiClient(client: mock, deviceId: 'test-device');
      final route = RouteController(api: api);
      await route.load();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: InventoryScreen(route: route),
        ),
      );
      await tester.pump();

      expect(find.text('Aaj ka stock'), findsOneWidget);
      expect(find.text('Lene hain (fulls)'), findsOneWidget);

      route.dispose();
    });
  });

  group('EarningsScreen unslop verification', () {
    testWidgets('error state renders AppButton retry CTA', (tester) async {
      final mock = MockClient((req) async => http.Response('{"error": "fail"}', 400));
      final api = ApiClient(client: mock, deviceId: 'test-device');
      final controller = EarningsController(api: api);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: EarningsScreen(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      final retryFinder = find.widgetWithText(AppButton, 'Dobara try karein');
      expect(retryFinder, findsOneWidget);
      final button = tester.widget<AppButton>(retryFinder);
      expect(button.kind, AppButtonKind.primary);
      expect(button.expand, isFalse);

      controller.dispose();
    });

    testWidgets('loaded state renders Custody token and Commission card', (tester) async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'stops_done': 12,
            'cash_total': 180000,
            'upi_total': 60000,
            'in_hand': 180000,
            'earned_payout': 24000,
            'flagged_stops': 0,
            'flagged_hold': 0,
          }),
          200,
        );
      });
      final api = ApiClient(client: mock, deviceId: 'test-device');
      final controller = EarningsController(api: api);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: EarningsScreen(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.text('Aapki Kamai (Commission)'), findsOneWidget);
      expect(find.text('Custody'), findsOneWidget);
      expect(find.text('Rs 240'), findsOneWidget);

      controller.dispose();
    });
  });

  group('SupportScreen unslop verification', () {
    testWidgets('queue error renders AppButton retry CTA', (tester) async {
      final mock = MockClient((req) async {
        return http.Response('{"error": "queue fail"}', 400);
      });
      final api = ApiClient(client: mock, deviceId: 'test-device');
      final controller = SupportController(api: api);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: SupportScreen(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      final retryFinder = find.widgetWithText(AppButton, 'Retry');
      expect(retryFinder, findsOneWidget);
      final button = tester.widget<AppButton>(retryFinder);
      expect(button.kind, AppButtonKind.secondary);
      expect(button.expand, isFalse);

      controller.dispose();
    });

    testWidgets('form renders AppButtons with primary/secondary kinds disabled until ID present', (tester) async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'complaint-101',
                'order_id': 'ord-1',
                'reason_code': 'broken_seal',
                'text': 'Seal was broken',
                'status': 'open',
              }
            ]
          }),
          200,
        );
      });
      final api = ApiClient(client: mock, deviceId: 'test-device');
      final controller = SupportController(api: api);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: SupportScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      final agreeFinder = find.widgetWithText(AppButton, 'सहमत हैं');
      final disagreeFinder = find.widgetWithText(AppButton, 'असहमत');
      expect(agreeFinder, findsOneWidget);
      expect(disagreeFinder, findsOneWidget);

      var agreeBtn = tester.widget<AppButton>(agreeFinder);
      var disagreeBtn = tester.widget<AppButton>(disagreeFinder);
      expect(agreeBtn.kind, AppButtonKind.primary);
      expect(disagreeBtn.kind, AppButtonKind.secondary);
      // Initially disabled because ID is empty
      expect(agreeBtn.onPressed, isNull);
      expect(disagreeBtn.onPressed, isNull);

      // Tap queue item to fill ID
      await tester.tap(find.textContaining('broken_seal'));
      await tester.pump();

      agreeBtn = tester.widget<AppButton>(agreeFinder);
      disagreeBtn = tester.widget<AppButton>(disagreeFinder);
      // Now enabled
      expect(agreeBtn.onPressed, isNotNull);
      expect(disagreeBtn.onPressed, isNotNull);

      controller.dispose();
    });
  });
}
