// Wave-1 UX tests (ADR-056): address Stepper sheet + login hero.
// MockClient, no backend.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/core/auth_impls.dart';
import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/addresses/address_screen.dart';
import 'package:shodasha_app/features/auth/auth_controller.dart';
import 'package:shodasha_app/features/auth/phone_screen.dart';

void main() {
  testWidgets('address add opens 3-step stepper', (tester) async {
    final mock = MockClient((req) async {
      if (req.method == 'GET') {
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response('not found', 404);
    });
    final controller =
        AddressController(api: ApiClient(client: mock, deviceId: 't'));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: AddressScreen(controller: controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    await tester.tap(find.text('Address add karein'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Naam'), findsOneWidget);
    expect(find.text('Pata'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('login shows hero card + trust chips + step header',
      (tester) async {
    final api = ApiClient(
        client: MockClient((_) async => http.Response('{}', 200)),
        deviceId: 't');
    final controller = AuthController(
      api: ApiBackedAuthApi(api),
      verifier: StubPhoneVerifier(),
      store: InMemorySessionStore(),
      deviceId: 't',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: PhoneScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('Shodasha'), findsOneWidget);
    expect(find.text('UPI + COD'), findsOneWidget);
    expect(find.text('WhatsApp help'), findsOneWidget);
    expect(find.text('Step 1 / 2 — Mobile number'), findsOneWidget);
    // Flush the hero entrance clock (flutter_animate delay timers) before
    // teardown — same pump pattern as the address test above.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    controller.dispose();
  });
}
