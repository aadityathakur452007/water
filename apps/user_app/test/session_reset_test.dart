// P0 regression — session boundary.
//
// App-scoped controllers must drop the previous account's data on
// logout/expiry, and a response that lands after the reset must be
// discarded (generation guard) instead of repopulating the list.
// Plugin-free: MockClient intercepts every request.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/features/addresses/address_screen.dart';
import 'package:shodasha_app/features/booking/booking_controller.dart';
import 'package:shodasha_app/features/orders/orders_controller.dart';
import 'package:shodasha_app/features/profile/profile_controller.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
      body == null ? '' : jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json'},
    );

Map<String, dynamic> _order(String id) => {
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
      'payment_status': 'unpaid',
      'state': 'placed',
      'window_start': '2026-10-22T08:00:00Z',
      'created_at': '2026-10-21T10:00:00Z',
    };

Map<String, dynamic> _address(String id) => {
      'id': id,
      'label': 'Home',
      'type': 'home',
      'phone': '9876543210',
      'pincode': '462001',
      'formatted': '1 Main Road',
      'is_default': true,
      'lat': 23.2,
      'lng': 77.4,
    };

void main() {
  group('session reset (never show the previous account)', () {
    test('OrdersController.reset clears rows and state', () async {
      final api = ApiClient(
        client: MockClient(
          (_) async => _json({
            'data': [_order('o1')],
            'next_cursor': null,
          }),
        ),
        accessToken: 't',
        deviceId: 'd',
      );
      final c = OrdersController(repo: ApiBackedOrdersRepository(api));
      await c.load();
      expect(c.totalCount, 1);

      c.reset();
      expect(c.totalCount, 0);
      expect(c.status, OrdersListStatus.initial);
      expect(c.isOffline, isFalse);
      expect(c.errorMessage, isNull);
      c.dispose();
    });

    test('a list response landing after reset is discarded', () async {
      final gate = Completer<void>();
      final api = ApiClient(
        client: MockClient((_) async {
          await gate.future;
          return _json({
            'data': [_order('o1')],
            'next_cursor': null,
          });
        }),
        accessToken: 't',
        deviceId: 'd',
      );
      final c = OrdersController(repo: ApiBackedOrdersRepository(api));
      final pending = c.load(); // in flight while the user logs out
      c.reset(); // session ended before the response arrived
      gate.complete();
      await pending;

      expect(c.totalCount, 0);
      expect(c.status, OrdersListStatus.initial);
      c.dispose();
    });

    test('AddressController.reset clears rows and selection', () async {
      final api = ApiClient(
        client: MockClient((_) async => _json([_address('a1')])),
        accessToken: 't',
        deviceId: 'd',
      );
      final c = AddressController(api: api);
      await c.load();
      c.select('a1');
      expect(c.items, hasLength(1));
      expect(c.selectedId, 'a1');

      c.reset();
      expect(c.items, isEmpty);
      expect(c.selectedId, isNull);
      expect(c.status, AddrStatus.initial);
      c.dispose();
    });

    test('ProfileController.reset drops the cached identity', () async {
      final api = ApiClient(
        client: MockClient(
          (_) async => _json({
            'user': {'id': 'u1', 'name': 'Asha', 'phone': '9876543210'},
          }),
        ),
        accessToken: 't',
        deviceId: 'd',
      );
      final c = ProfileController(api: api);
      await c.load();
      expect(c.user, isNotNull);
      expect(c.status, ProfileStatus.loaded);

      c.reset();
      expect(c.user, isNull);
      expect(c.status, ProfileStatus.initial);
      c.dispose();
    });

    test('BookingController.resetUserScoped drops ledger, lines and key', () {
      final c = BookingController();
      c.applyLedger(dues: 5000, held: 2, depositPaid: 15000);
      c.setRefill(2);
      c.setContainer(1);
      c.ensureIdempotencyKey();

      c.resetUserScoped();
      expect(c.duesPaise, 0);
      expect(c.heldJars, 0);
      expect(c.depositPaidPaise, 0);
      expect(c.totalJars, 0);
      expect(c.idempotencyKey, isNull);
      c.dispose();
    });

    test('payload changes rotate the key; retries reuse it', () {
      final c = BookingController();
      final first = c.ensureIdempotencyKey();
      expect(c.ensureIdempotencyKey(), first, reason: 'retry replays');

      c.setRefill(1); // payload changed → new key
      final second = c.idempotencyKey!;
      expect(second, isNot(first));

      c.paymentMode = PaymentMode.cod; // payload changed → new key
      expect(c.idempotencyKey, isNot(second));
      c.dispose();
    });
  });
}
