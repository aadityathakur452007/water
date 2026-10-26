// S7 payments-history spec — ported from legacy payment_history_test.dart and
// adapted to the donor-English copy + the new wallet folder.
//
// Plugin-free: mocked http only. Covers unauthorised (zero network), mapping,
// loaded cards, honest empty, and session-expired copy on 401.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/wallet/payment_history_screen.dart';

Widget _app(ApiClient api) => MaterialApp(
  theme: buildShodashaTheme(),
  home: PaymentHistoryScreen(api: api),
);

void main() {
  test('PaymentRecord maps the server row (paise, display method)', () {
    final p = PaymentRecord.fromApi({
      'id': 'pay_123',
      'order_id': 'ord_456',
      'amount': 5600,
      'method': 'upi',
      'provider_ref': 'pay_ref_test',
      'status': 'paid',
      'created_at': '2026-10-11T12:00:00Z',
      'verified_at': '2026-10-11T12:00:05Z',
      'jars_count': 2,
      'deposit_due': 15000,
      'water_bill': 5600,
    });
    expect(p.amountPaise, 5600);
    expect(p.method, 'UPI');
    expect(p.status, 'paid');
    expect(p.isPaid, isTrue);
    expect(p.jarsCount, 2);
    expect(p.depositPaise, 15000);
    expect(p.providerRef, 'pay_ref_test');
    expect(p.dateIso, '2026-10-11T12:00:05Z');
  });

  testWidgets('unauthenticated client shows login prompt without network', (
    tester,
  ) async {
    var networkHits = 0;
    final mock = MockClient((req) async {
      networkHits += 1;
      return http.Response('{"data": []}', 200);
    });
    final api = ApiClient(client: mock, deviceId: 'test-device');

    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(networkHits, 0);
    expect(find.text('Log in to view your payments'), findsOneWidget);
  });

  testWidgets('authenticated client renders server payment cards', (
    tester,
  ) async {
    final mock = MockClient((req) async {
      if (req.url.path.contains('/payments/me')) {
        expect(req.url.queryParameters['limit'], '50');
        expect(req.headers['Authorization'], 'Bearer valid-test-token');
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
              },
            ],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final api = ApiClient(
      client: mock,
      deviceId: 'test-device',
      accessToken: 'valid-test-token',
    );

    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('Payments & deposits'), findsOneWidget);
    expect(find.text('₹56'), findsOneWidget);
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('2 jars delivered'), findsOneWidget);
    expect(find.text('Ref: pay_ref_test'), findsOneWidget);
  });

  testWidgets('empty history shows a teaching empty state', (tester) async {
    final mock = MockClient((req) async {
      return http.Response(jsonEncode({'data': []}), 200);
    });
    final api = ApiClient(
      client: mock,
      deviceId: 'test-device',
      accessToken: 'valid-test-token',
    );

    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('No payments yet'), findsOneWidget);
    expect(
      find.text(
        'Your UPI and cash payments and deposit refunds will appear here.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('401 shows session-expired copy and retry', (tester) async {
    final mock = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'error': {'code': 'UNAUTH', 'message': 'Unauthorized', 'details': {}},
        }),
        401,
      );
    });
    final api = ApiClient(
      client: mock,
      deviceId: 'test-device',
      accessToken: 'expired-token',
    );

    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('Session expired — log in again'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
