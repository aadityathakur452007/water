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
import 'package:vendor_app/features/sync/sync_controller.dart';
import 'package:vendor_app/features/sync/sync_screen.dart';
import 'package:vendor_app/shared/ui/app_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DutyScreen in error state renders AppButton retry CTA', (tester) async {
    final mockClient = MockClient((req) async {
      return http.Response(jsonEncode({'error': 'Test error'}), 400);
    });
    final api = ApiClient(client: mockClient, deviceId: 'test-device');
    final controller = DutyController(api: api);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: DutyScreen(controller: controller),
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

  testWidgets('DutyScreen off-duty dialog renders AppButton danger CTA', (tester) async {
    final mockClient = MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/vendor/profile')) {
        return http.Response(
          jsonEncode({
            'user_id': 'v1',
            'on_duty': true,
          }),
          200,
        );
      }
      if (p.endsWith('/vendor/routes/today')) {
        return http.Response(
          jsonEncode({
            'route': {'id': 'r1'},
            'stops': [],
            'skip': [],
            'loading': {'take_fulls': 0, 'expect_empties': 0},
          }),
          200,
        );
      }
      return http.Response('{"status":"ok"}', 200);
    });
    final api = ApiClient(client: mockClient, deviceId: 'test-device');
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

    // Tap switch to turn off duty
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.text('Duty off karein?'), findsOneWidget);
    final confirmFinder = find.widgetWithText(AppButton, 'Haan, off karein');
    expect(confirmFinder, findsOneWidget);
    final button = tester.widget<AppButton>(confirmFinder);
    expect(button.kind, AppButtonKind.danger);
    expect(button.expand, isFalse);

    controller.dispose();
  });

  testWidgets('SyncScreen renders canonical AppButton for manual sync action', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final mockClient = MockClient((req) async {
      return http.Response(jsonEncode({'applied': [], 'rejected': []}), 200);
    });
    final api = ApiClient(client: mockClient, deviceId: 'test-device');
    final controller = SyncController(api: api);
    await controller.load();
    await controller.enqueue(stopId: 'stop-42', triple: {'fulls_given': 2, 'empties_back': 2});

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: SyncScreen(controller: controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final syncFinder = find.widgetWithText(AppButton, 'Abhi sync karein (1)');
    expect(syncFinder, findsOneWidget);
    final button = tester.widget<AppButton>(syncFinder);
    expect(button.kind, AppButtonKind.primary);
    expect(button.icon, Icons.sync);
    expect(button.busy, isFalse);

    controller.dispose();
  });
}
