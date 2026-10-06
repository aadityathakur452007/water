// Wave-1 UX tests (ADR-056): Route sections, support enable + queue,
// duty-off confirm. MockClient, no backend.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/core/theme.dart';
import 'package:vendor_app/features/duty/duty_controller.dart';
import 'package:vendor_app/features/duty/duty_screen.dart';
import 'package:vendor_app/features/route/route_controller.dart';
import 'package:vendor_app/features/route/route_screen.dart';
import 'package:vendor_app/features/support/support_controller.dart';
import 'package:vendor_app/features/support/support_screen.dart';

MockClient _mock() => MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/vendor/routes/today')) {
        return http.Response(
            jsonEncode({
              'route': {'id': 'r1'},
              'stops': [],
              'skip': [],
              'loading': {'take_fulls': 0, 'expect_empties': 0},
            }),
            200);
      }
      // Phase 5 §5.3: duty truth rides the profile read (on-duty here).
      if (p.endsWith('/vendor/profile')) {
        return http.Response(
            jsonEncode({'user_id': 'v1', 'on_duty': true}), 200);
      }
      if (p.endsWith('/vendor/complaints')) {
        return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'c1',
                  'order_id': 'o1',
                  'reason_code': 'short_delivery',
                  'text': 'one short',
                  'status': 'open',
                }
              ]
            }),
            200);
      }
      return http.Response('not found', 404);
    });

void main() {
  testWidgets('route exposes customers search + tappable sync chip',
      (tester) async {
    var customersOpened = false;
    var syncOpened = false;
    final api = ApiClient(client: _mock(), deviceId: 't');
    final controller = RouteController(api: api)..pendingSync = 2;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: RouteScreen(
          controller: controller,
          onOpenStop: (_) {},
          onOpenCustomers: () => customersOpened = true,
          onOpenSync: () => syncOpened = true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    await tester.tap(find.byTooltip('Customers khojein'));
    expect(customersOpened, isTrue);
    await tester.tap(find.textContaining('Sync baaki (2)'));
    await tester.pump();
    expect(syncOpened, isTrue);
    controller.dispose();
  });

  testWidgets('support agree enables after typing + queue lists',
      (tester) async {
    final api = ApiClient(client: _mock(), deviceId: 't');
    final controller = SupportController(api: api);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: SupportScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // Queue from the server renders; tap fills the verify id.
    expect(find.textContaining('short_delivery'), findsOneWidget);
    await tester.tap(find.textContaining('short_delivery'));
    await tester.pump();
    expect(find.text('Sahmat / Agree'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('duty-off asks for confirmation first', (tester) async {
    final api = ApiClient(client: _mock(), deviceId: 't');
    final controller = DutyController(api: api);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: DutyScreen(controller: controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(controller.onDuty, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.text('Duty off karein?'), findsOneWidget);

    await tester.tap(find.text('Rehne dein'));
    await tester.pump();
    expect(controller.onDuty, isTrue);
    expect(find.text('Duty off karein?'), findsNothing);
    controller.dispose();
  });
}
