import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/features/booking/booking_controller.dart';
import 'package:shodasha_donor/features/booking/checkout_service.dart';

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

void main() {
  test(
    'replayed create reuses the original order and the same UPI key',
    () async {
      const idemKey = 'idem-replay-1';
      final keysSeen = <String>[];
      var createCalls = 0;
      var intentCalls = 0;

      final client = MockClient((request) async {
        final idem = request.headers['Idempotency-Key'] ?? '';
        if (request.url.path.endsWith('/orders')) {
          createCalls++;
          keysSeen.add(idem);
          expect(
            jsonDecode(request.body)['window_start'],
            '2026-10-26T08:00:00',
          );
          // The first create committed but its response was lost: the server
          // replays the original row inside the 409 envelope.
          return _json({
            'error': {
              'code': 'IDEMPOTENT_REPLAY',
              'message': 'This request was already processed.',
              'details': {
                'order': {
                  'id': 'ord-1',
                  'total': 5600,
                  'water_bill': 5600,
                  'deposit_due': 0,
                  'payment_mode': 'upi',
                },
              },
            },
          }, 409);
        }
        if (request.url.path.endsWith('/payments/upi-intent')) {
          intentCalls++;
          keysSeen.add(idem);
          expect(jsonDecode(request.body)['order_id'], 'ord-1');
          return _json({
            'payment': {'id': 'pay-1'},
            'provider_ref': 'FAKE-1',
            'link': 'upi://pay?pa=shodasha@upi&am=56.00',
          }, 200);
        }
        fail('unexpected request ${request.method} ${request.url}');
      });

      final api = ApiClient(
        client: client,
        baseUrl: 'https://api.example.test/v1',
        accessToken: 'test-token',
      );
      final controller = BookingController()
        ..setRefill(2)
        ..paymentMode = PaymentMode.upi;
      // Pin the key so the assertions cover key REUSE, not uuid randomness.
      controller.idempotencyKey = idemKey;

      final result = await placeCheckout(
        api: api,
        controller: controller,
        addressId: 'addr-1',
        windowStart: '2026-10-26T08:00:00',
        windowLabel: '8:00–8:30 AM',
        quote: {
          'total': 5600,
          'water_bill': 5600,
          'deposit_due': 0,
          'rate_version': 'v1',
          'quote_hash': 'hash-123',
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 15))
              .toIso8601String(),
        },
      );

      expect(createCalls, 1);
      expect(intentCalls, 1);
      expect(keysSeen, [idemKey, idemKey]);
      expect(result.orderId, 'ord-1');
      expect(result.totalPaise, 5600);
      expect(result.providerRef, 'FAKE-1');
    },
  );
}
