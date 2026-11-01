import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/features/route/route_controller.dart';
import 'package:vendor_app/features/route/route_screen.dart';
import 'package:vendor_app/features/stops/stop_detail_screen.dart';
import 'package:vendor_app/features/stops/stops_controller.dart';
import 'package:vendor_app/shared/ui/app_button.dart';

MockClient _mockClient() => MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/vendor/routes/today')) {
        return http.Response(
          jsonEncode({
            'route': {'id': 'r-1', 'date': '2026-11-01', 'status': 'in_progress'},
            'stops': [
              {
                'id': 'stop-1',
                'seq': 1,
                'customer_id': 'u1',
                'customer_name': 'Amit Sharma',
                'customer_phone': '9876543210',
                'address': 'Plot 42, MP Nagar Zone 2, Bhopal',
                'lat': 23.2332,
                'lng': 77.4343,
                'fulls_exp': 2,
                'empties_exp': 2,
                'cash_due': 16000,
                'total': 16000,
                'version': 1,
                'status': 'pending',
                'payment_mode': 'cod',
                'payment_status': 'unpaid',
              }
            ],
            'skipped': [],
            'summary': {'take_fulls': 2, 'expect_empties': 2},
          }),
          200,
        );
      }
      if (p.endsWith('/vendor/stops/stop-1')) {
        return http.Response(
          jsonEncode({
            'id': 'stop-1',
            'seq': 1,
            'customer_id': 'u1',
            'customer_name': 'Amit Sharma',
            'customer_phone': '9876543210',
            'address': 'Plot 42, MP Nagar Zone 2, Bhopal',
            'lat': 23.2332,
            'lng': 77.4343,
            'fulls_exp': 2,
            'empties_exp': 2,
            'cash_due': 16000,
            'total': 16000,
            'version': 1,
            'status': 'pending',
            'payment_mode': 'cod',
            'payment_status': 'unpaid',
            'held': 2,
            'deposit_balance': 30000,
            'dues': 0,
            'hold_blocked': false,
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

void main() {
  test('RouteStop parses coordinates lat and lng fromJson', () {
    final stop = RouteStop.fromJson({
      'id': 'stop-1',
      'seq': 1,
      'customer_name': 'Amit',
      'address': 'Bhopal',
      'lat': 23.2332,
      'lng': 77.4343,
      'fulls_exp': 1,
      'empties_exp': 1,
      'cash_due': 8000,
      'version': 1,
      'status': 'pending',
    });

    expect(stop.lat, 23.2332);
    expect(stop.lng, 77.4343);
  });

  testWidgets('RouteScreen stockout prompt renders AppButton danger CTA', (tester) async {
    final apiClient = ApiClient(client: _mockClient(), deviceId: 'test-device');
    final controller = RouteController(api: apiClient);

    await tester.pumpWidget(
      MaterialApp(
        home: RouteScreen(
          controller: controller,
          onOpenStop: (_) {},
          api: apiClient,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tap SOS button in AppBar
    final sosBtn = find.byTooltip('Stock Khatam (SOS)');
    expect(sosBtn, findsOneWidget);
    await tester.tap(sosBtn);
    await tester.pumpAndSettle();

    // Verify AlertDialog renders AppButton with danger kind
    final stockoutBtn = find.widgetWithText(AppButton, 'Report Stockout');
    expect(stockoutBtn, findsOneWidget);
    final appButton = tester.widget<AppButton>(stockoutBtn);
    expect(appButton.kind, AppButtonKind.danger);

    // Cancel dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('StopDetailScreen renders canonical AppButtons and coordinate navigation action', (tester) async {
    final apiClient = ApiClient(client: _mockClient(), deviceId: 'test-device');
    final controller = StopsController(api: apiClient);

    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: StopDetailScreen(
          controller: controller,
          stopId: 'stop-1',
          stopLabel: 'Stop 1 · Amit Sharma',
        ),
      ),
    );

    // Initial pump and load stop
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Check Customer details and action buttons
    expect(find.text('Amit Sharma'), findsOneWidget);
    expect(find.text('Call customer'), findsOneWidget);
    expect(find.text('Navigate'), findsOneWidget);

    // Verify AppButtons for Delivery Handover, Cash collection, and RTO Issue reporting
    final handoverFinder = find.widgetWithText(AppButton, 'Delivery Handover (Bottles + OTP)');
    expect(handoverFinder, findsOneWidget);
    expect(tester.widget<AppButton>(handoverFinder).kind, AppButtonKind.primary);

    final cashFinder = find.widgetWithText(AppButton, 'Cash jama karein (Rs 160)');
    expect(cashFinder, findsOneWidget);
    expect(tester.widget<AppButton>(cashFinder).kind, AppButtonKind.money);

    final rtoFinder = find.widgetWithText(AppButton, 'समस्या दर्ज करें (RTO)');
    expect(rtoFinder, findsOneWidget);
    expect(tester.widget<AppButton>(rtoFinder).kind, AppButtonKind.danger);
  });
}
