import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/core/auth_impls.dart';
import 'package:vendor_app/core/theme.dart';
import 'package:vendor_app/features/auth/auth_controller.dart';
import 'package:vendor_app/features/customers/customers_controller.dart';
import 'package:vendor_app/features/duty/duty_controller.dart';
import 'package:vendor_app/features/earnings/earnings_controller.dart';
import 'package:vendor_app/features/route/route_controller.dart';
import 'package:vendor_app/features/shell/more_hub_screen.dart';
import 'package:vendor_app/features/shell/vendor_shell.dart';
import 'package:vendor_app/features/stops/stops_controller.dart';
import 'package:vendor_app/features/support/support_controller.dart';
import 'package:vendor_app/features/sync/sync_controller.dart';

void main() {
  testWidgets('VendorShell off-duty shows soft banner & locked route, but allows Earnings & More', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool dutyOn = false;

    final mock = MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/vendor/profile')) {
        return http.Response(jsonEncode({'user_id': 'v1', 'on_duty': dutyOn}), 200);
      }
      if (p.endsWith('/vendor/duty')) {
        dutyOn = true;
        return http.Response(jsonEncode({'duty_on': true, 'since': 'now', 'repooled': 0}), 200);
      }
      if (p.endsWith('/vendor/routes/today')) {
        return http.Response(jsonEncode({'route': {'id': 'r1'}, 'stops': [], 'loading': {}}), 200);
      }
      if (p.endsWith('/vendor/earnings')) {
        return http.Response(jsonEncode({
          'shift': '2026-10-31', 'stops_done': 0, 'cash_total': 0, 'upi_total': 0,
          'earned_payout': 0, 'flagged_stops': 0, 'flagged_hold': 0,
        }), 200);
      }
      if (p.endsWith('/vendor/customers')) {
        return http.Response(jsonEncode({'date': '2026-10-31', 'customers': []}), 200);
      }
      if (p.endsWith('/vendor/complaints')) {
        return http.Response(jsonEncode({'complaints': []}), 200);
      }
      return http.Response('not found', 404);
    });

    final api = ApiClient(client: mock, deviceId: 'test-device');
    final auth = AuthController(api: ApiBackedAuthApi(api), store: InMemorySessionStore());
    final duty = DutyController(api: api);
    final route = RouteController(api: api);
    final stops = StopsController(api: api);
    final sync = SyncController(api: api);
    final earnings = EarningsController(api: api);
    final support = SupportController(api: api);
    final customers = CustomersController(api: api);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: VendorShell(
          auth: auth,
          duty: duty,
          route: route,
          stops: stops,
          sync: sync,
          earnings: earnings,
          support: support,
          customers: customers,
          meLoader: () async => {'name': 'Vendor 1'},
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify soft sticky banner appears (DEF-07)
    expect(find.text('Currently Off Duty (छुट्टी पर हैं)'), findsOneWidget);
    expect(find.text('You are currently Off Duty'), findsOneWidget);

    // Switch to Earnings tab (Tab 1) while off duty
    await tester.tap(find.byIcon(Icons.payments_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Earnings / कमाई'), findsOneWidget);

    // Switch to More tab (Tab 3) - DEF-05: verify MoreHubScreen renders without opening drawer
    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(MoreHubScreen), findsOneWidget);
    expect(find.text('Customers (ग्राहक)'), findsOneWidget);
    expect(find.text('Stock (स्टॉक)'), findsOneWidget);
    expect(find.text('Sync Log (सिंक स्थिति)'), findsOneWidget);
    expect(find.text('Profile (प्रोफ़ाइल)'), findsOneWidget);

    // Switch back to Route tab (Tab 0)
    await tester.tap(find.byIcon(Icons.route_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Go On Duty (ड्यूटी शुरू करें)'), findsOneWidget);

    // Tap "Go On Duty" to go on duty
    await tester.tap(find.text('Go On Duty (ड्यूटी शुरू करें)'));
    await tester.pumpAndSettle();

    // Banner and lock should be gone
    expect(find.text('Currently Off Duty (छुट्टी पर हैं)'), findsNothing);
    expect(find.text('You are currently Off Duty'), findsNothing);
  });
}
