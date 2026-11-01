// Unit tests for the unified HandoverSheet component.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/core/theme.dart';
import 'package:vendor_app/features/stops/handover_sheet.dart';
import 'package:vendor_app/features/stops/stops_controller.dart';

void main() {
  late ApiClient api;
  late StopsController controller;

  setUp(() {
    final mock = MockClient((request) async {
      return http.Response('{"status":"ok"}', 200);
    });
    api = ApiClient(client: mock, deviceId: 'test-device');
    controller = StopsController(api: api);
  });

  testWidgets('HandoverSheet starts on Step 1 when triple is not yet done', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: Scaffold(
          body: HandoverSheet(
            controller: controller,
            stopId: 'stop-123',
            fullsExp: 2,
            emptiesExp: 2,
            tripleAlreadyDone: false,
          ),
        ),
      ),
    );

    expect(find.text('Doorstep Handover (1/2)'), findsOneWidget);
    expect(find.text('Step 1: Bottles'), findsOneWidget);
    expect(find.text('Aage: Customer OTP'), findsOneWidget);

    // Tap next to go to Step 2
    await tester.tap(find.text('Aage: Customer OTP'));
    await tester.pumpAndSettle();

    expect(find.text('Customer OTP (2/2)'), findsOneWidget);
    expect(find.text('Step 2: Verify'), findsOneWidget);
    expect(find.text('Customer Delivery OTP'), findsOneWidget);
    expect(find.text('Peechhe'), findsOneWidget);
  });

  testWidgets('HandoverSheet starts directly on Step 2 when triple is already done', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: Scaffold(
          body: HandoverSheet(
            controller: controller,
            stopId: 'stop-123',
            fullsExp: 2,
            emptiesExp: 2,
            tripleAlreadyDone: true,
          ),
        ),
      ),
    );

    expect(find.text('Customer OTP (2/2)'), findsOneWidget);
    expect(find.text('Step 2: Verify'), findsOneWidget);
    expect(find.text('Customer Delivery OTP'), findsOneWidget);
    // When triple is already done, Peechhe is not shown
    expect(find.text('Peechhe'), findsNothing);
  });
}
