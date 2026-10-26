// P0 regression — duplicate order/subscription after a post-create failure.
//
// Law: once the server has minted an order, nothing in the recovery path may
// re-post create. The payment step retries with the SAME idempotency key, and
// the sheet offers "Check Orders" instead of a generic Retry. An unusable
// create response sends the user to Orders (never a blind retry).
// Plugin-free: MockClient intercepts every request; intent failures use 400
// so ApiClient's retry loop does not interfere with call counting.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/addresses/address_screen.dart';
import 'package:shodasha_app/features/booking/booking_controller.dart';
import 'package:shodasha_app/features/booking/booking_sheet.dart';
import 'package:shodasha_app/features/booking/checkout_service.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
      body == null ? '' : jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json'},
    );

Map<String, dynamic> _quote() => {
      'total': 2800,
      'quote_hash': 'h1',
      'expires_at': '2099-01-01T00:00:00Z',
      'rate_version': 'v1',
      'water_bill': 2800,
      'deposit_due': 0,
      'cap_note': '',
    };

Map<String, dynamic> _orderJson({String id = 'o1'}) => {
      'id': id,
      'items': [
        {'sku': 'refill', 'qty': 1},
      ],
      'n': 1,
      'e': 0,
      'water_bill': 2800,
      'deposit_due': 0,
      'cap_charge': 0,
      'total': 2800,
      'payment_mode': 'upi',
      'payment_status': 'pending',
      'state': 'placed',
      'window_start': '2026-10-22T08:00:00Z',
      'created_at': '2026-10-21T10:00:00Z',
    };

Map<String, dynamic> _address() => {
      'id': 'a1',
      'label': 'Home',
      'type': 'home',
      'phone': '9876543210',
      'pincode': '462001',
      'formatted': '1 Main Road',
      'is_default': true,
      'lat': 23.2,
      'lng': 77.4,
    };

String _idem(http.Request r) =>
    r.headers['Idempotency-Key'] ?? r.headers['idempotency-key'] ?? '';

void main() {
  group('placeCheckout — create is never repeated', () {
    test('intent failure returns attention (no throw) and one order POST',
        () async {
      final log = <http.Request>[];
      var intentCalls = 0;
      final api = ApiClient(
        client: MockClient((req) async {
          log.add(req);
          final path = req.url.path;
          if (req.method == 'POST' && path.endsWith('/orders')) {
            return _json({'order': _orderJson()}, 201);
          }
          if (req.method == 'POST' && path.endsWith('/payments/upi-intent')) {
            intentCalls++;
            return _json({'detail': 'gateway down'}, 400);
          }
          return _json({}, 404);
        }),
        accessToken: 't',
        deviceId: 'd',
      );
      final c = BookingController()..setRefill(1);

      final result = await placeCheckout(
        api: api,
        controller: c,
        addressId: 'a1',
        windowStart: '2026-10-22T08:00:00',
        windowLabel: 'Tomorrow, 8–12',
        quote: _quote(),
      );

      expect(result.orderId, 'o1');
      expect(result.attention, isTrue);
      expect(result.attentionMessage, contains('check Orders'));
      expect(result.upiLink, isEmpty);

      final orderPosts = log
          .where((r) => r.method == 'POST' && r.url.path.endsWith('/orders'))
          .toList();
      expect(orderPosts, hasLength(1));
      expect(intentCalls, 1);
      // The payment step replays the SAME key the create used.
      final intentRequests = log
          .where((r) => r.url.path.endsWith('/payments/upi-intent'))
          .toList();
      expect(intentRequests, hasLength(1));
      expect(_idem(intentRequests.single), _idem(orderPosts.single));
      expect(_idem(orderPosts.single), isNotEmpty);

      // Sheet's "Retry payment" path: same key, no second create.
      final key = c.ensureIdempotencyKey();
      await expectLater(
        api.upiIntent(orderId: result.orderId, idempotencyKey: key),
        throwsA(isA<ApiException>()),
      );
      expect(
        log.where((r) => r.method == 'POST' && r.url.path.endsWith('/orders')),
        hasLength(1),
      );
      expect(c.idempotencyKey, key, reason: 'retry never rotates the key');
      c.dispose();
    });

    test('unusable create response throws UnconfirmedCreateException',
        () async {
      var orderPosts = 0;
      var intentCalls = 0;
      final api = ApiClient(
        client: MockClient((req) async {
          final path = req.url.path;
          if (req.method == 'POST' && path.endsWith('/orders')) {
            orderPosts++;
            // Created server-side but the id is missing on the wire.
            return _json({
              'order': {'total': 2800, 'payment_status': 'pending'},
            }, 201);
          }
          if (path.endsWith('/payments/upi-intent')) {
            intentCalls++;
            return _json({}, 500);
          }
          return _json({}, 404);
        }),
        accessToken: 't',
        deviceId: 'd',
      );
      final c = BookingController()..setRefill(1);

      await expectLater(
        placeCheckout(
          api: api,
          controller: c,
          addressId: 'a1',
          windowStart: '2026-10-22T08:00:00',
          windowLabel: 'Tomorrow, 8–12',
          quote: _quote(),
        ),
        throwsA(isA<UnconfirmedCreateException>()),
      );

      expect(orderPosts, 1);
      expect(intentCalls, 0, reason: 'no payment step without an order id');
      c.dispose();
    });
  });

  group('checkout sheet recovery UI', () {
    testWidgets('payment failure offers Retry payment / Check Orders and '
        'retrying adds no second order', (tester) async {
      final log = <http.Request>[];
      var intentCalls = 0;
      final api = ApiClient(
        client: MockClient((req) async {
          log.add(req);
          final path = req.url.path;
          if (path.endsWith('/windows')) {
            return _json({
              'windows': [
                {'start': '08:00', 'end': '12:00'},
              ],
              'date': '2026-10-22',
              'serviceable': true,
            });
          }
          if (path.endsWith('/quotes')) return _json(_quote());
          if (path.endsWith('/addresses') && req.method == 'GET') {
            return _json([_address()]);
          }
          if (req.method == 'POST' && path.endsWith('/orders')) {
            return _json({'order': _orderJson()}, 201);
          }
          if (req.method == 'POST' && path.endsWith('/payments/upi-intent')) {
            intentCalls++;
            return _json({'detail': 'gateway down'}, 400);
          }
          return _json({}, 404);
        }),
        accessToken: 't',
        deviceId: 'd',
      );
      final c = BookingController()..setRefill(1);
      CheckoutResult? done;

      await tester.pumpWidget(MaterialApp(
        theme: buildShodashaTheme(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showCheckoutSheet(
                  ctx,
                  controller: c,
                  api: api,
                  razorpayKeyId: '',
                  address: const AddressEntry(
                    id: 'a1',
                    label: 'Home',
                    type: AddrType.home,
                    phone: '9876543210',
                    pincode: '462001',
                    addressLine: '1 Main Road',
                  ),
                  onChangeAddress: () {},
                  onDone: (r) => done = r,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('PAY'));
      await tester.pumpAndSettle();

      // The order exists — honest recovery, no COD switch, no blind Retry.
      expect(find.textContaining('check Orders'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry payment'));
      expect(find.text('Retry payment'), findsOneWidget);
      expect(find.text('Check Orders'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Choose COD'), findsNothing);

      int orderPosts() => log
          .where((r) => r.method == 'POST' && r.url.path.endsWith('/orders'))
          .length;
      expect(orderPosts(), 1);
      expect(intentCalls, 1);

      // Retry payment: re-requests the intent only, never create.
      await tester.tap(find.text('Retry payment'));
      await tester.pumpAndSettle();
      expect(orderPosts(), 1);
      expect(intentCalls, 2);
      expect(
        find.text('The payment link is still unavailable. Try again or '
            'check Orders.'),
        findsOneWidget,
      );

      // Check Orders hands the created result back to the shell.
      await tester.tap(find.text('Check Orders'));
      await tester.pumpAndSettle();
      expect(done, isNotNull);
      expect(done!.orderId, 'o1');
      expect(done!.attention, isTrue);
      expect(orderPosts(), 1);
      c.dispose();
    });
  });
}
