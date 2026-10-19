// PaymentHistoryScreen widget and auth tests.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/features/profile/payment_history_screen.dart';

void main() {
  testWidgets('unauthenticated client shows login required without firing network',
      (tester) async {
    var networkHits = 0;
    final mock = MockClient((req) async {
      networkHits += 1;
      return http.Response('{"data": []}', 200);
    });
    // ApiClient without token
    final api = ApiClient(client: mock, deviceId: 'test-device');

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentHistoryScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(networkHits, 0);
    expect(find.text('Payments dekhne ke liye login karein'), findsOneWidget);
  });

  testWidgets('authenticated client loads and displays payment cards',
      (tester) async {
    final mock = MockClient((req) async {
      if (req.url.path.contains('/payments/me')) {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'pay_123',
                'order_id': 'ord_456',
                'amount': 5600,
                'method': 'upi',
                'provider_ref': 'pay_ref_test',
                'status': 'paid',
                'created_at': '2026-10-11T12:00:00Z',
                'verified_at': '2026-10-11T12:00:05Z',
                'jars_count': 2,
                'deposit_due': 0,
                'water_bill': 5600,
              }
            ]
          }),
          200,
        );
      }
      return http.Response('Not found', 404);
    });

    final api = ApiClient(
      client: mock,
      deviceId: 'test-device',
      accessToken: 'valid-test-bearer-token',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentHistoryScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mere Payments'), findsOneWidget);
    expect(find.text('₹56'), findsOneWidget);
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('Safal / Paid'), findsOneWidget);
    expect(find.text('2 Jars delivered'), findsOneWidget);
  });

  testWidgets('empty payment history shows friendly empty state',
      (tester) async {
    final mock = MockClient((req) async {
      return http.Response(jsonEncode({'data': []}), 200);
    });

    final api = ApiClient(
      client: mock,
      deviceId: 'test-device',
      accessToken: 'valid-test-bearer-token',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentHistoryScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Koi payment record nahi mila'), findsOneWidget);
  });

  testWidgets('401 response displays session expired message', (tester) async {
    final mock = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'error': {'code': 'UNAUTH', 'message': 'Unauthorized', 'details': {}}
        }),
        401,
      );
    });

    final api = ApiClient(
      client: mock,
      deviceId: 'test-device',
      accessToken: 'expired-token',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentHistoryScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Session expire ho gaya — dobara login karein'), findsOneWidget);
  });
}
