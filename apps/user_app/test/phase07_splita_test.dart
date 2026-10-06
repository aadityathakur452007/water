// Phase 7 Split A — honesty checks: address identity, tracker banners,
// slots failure LOUD, server estimate on Pay, confirm content. No backend.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/features/addresses/address_screen.dart';
import 'package:shodasha_app/features/booking/booking_controller.dart';
import 'package:shodasha_app/features/booking/booking_sheet.dart';
import 'package:shodasha_app/features/booking/checkout_service.dart';
import 'package:shodasha_app/features/booking/quote_confirm.dart';
import 'package:shodasha_app/features/orders/orders_controller.dart';
import 'package:shodasha_app/features/orders/tracking_screen.dart';

Order _order(String id, OrderState state) => Order(
  id: id,
  state: state,
  windowStart: DateTime(2026, 10, 6, 8),
  windowEnd: DateTime(2026, 10, 6, 8, 30),
);

AddressEntry _addr() => const AddressEntry(
  id: 'a1',
  label: 'Home',
  type: AddrType.home,
  phone: '+919302190067',
  pincode: '110001',
  addressLine: 'H1, Street',
);

ApiClient _api(Future<http.Response> Function(http.BaseRequest) fn) =>
    ApiClient(client: MockClient(fn), deviceId: 't');

Future<void> _pumpSheet(
  WidgetTester tester, {
  required BookingController controller,
  required ApiClient api,
  AddressEntry? address,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showCheckoutSheet(
              ctx,
              controller: controller,
              api: api,
              razorpayKeyId: '',
              address: address ?? _addr(),
              onChangeAddress: () {},
              onDone: (_) {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('addressStillListed', () {
    test('listed / missing / malformed / empty / non-list', () {
      expect(
        addressStillListed([
          {'id': 'a1'},
          {'id': 'a2'},
        ], 'a1'),
        isTrue,
      );
      expect(
        addressStillListed([
          {'id': 'a1'},
        ], 'a9'),
        isFalse,
      );
      expect(
        addressStillListed([
          {'nope': 1},
        ], 'a1'),
        isFalse,
      );
      expect(
        addressStillListed([
          {'id': 'a1'},
        ], ''),
        isFalse,
      );
      expect(addressStillListed('nope', 'a1'), isFalse);
      expect(addressStillListed(null, 'a1'), isFalse);
    });
  });

  group('tracker terminal banners', () {
    for (final entry in {
      OrderState.failed: 'Delivery fail ho gayi',
      OrderState.rejected: 'Order reject ho gaya',
      OrderState.cancelled: 'Order cancel ho gaya',
    }.entries) {
      testWidgets('${entry.key.name} shows its own banner', (tester) async {
        final c = OrdersController(
          repo: StubOrdersRepository([_order('o1', entry.key)]),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: TrackingScreen(controller: c, orderId: 'o1'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.textContaining(entry.value), findsOneWidget);
        // Failed/rejected must never show the delivered banner.
        expect(find.text('Order deliver ho gaya'), findsNothing);
        c.stopTracking();
        c.dispose();
      });
    }

    testWidgets('delivered shows the full tracker, not a banner', (
      tester,
    ) async {
      final c = OrdersController(
        repo: StubOrdersRepository([_order('o1', OrderState.delivered)]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TrackingScreen(controller: c, orderId: 'o1'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Mil gaya'), findsOneWidget);
      expect(find.text('Order deliver ho gaya'), findsNothing);
      c.stopTracking();
      c.dispose();
    });
  });

  group('slots failure LOUD', () {
    testWidgets('fetch error blocks Pay with banner + retry', (tester) async {
      // 400 (not retryable) keeps the failure deterministic — the banner
      // path is identical for any ApiException.
      final api = _api((req) async {
        if (req.url.path.endsWith('/windows')) {
          return http.Response('bad', 400);
        }
        return http.Response('not found', 404);
      });
      final c = BookingController();
      await _pumpSheet(tester, controller: c, api: api);
      // Once-orders collapse to Address → Pay: one Aage lands on Pay.
      await tester.tap(find.text('Aage badhein'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      // Schedule recap renders (read-only prefill, no re-ask) …
      expect(find.textContaining('Ek baar'), findsOneWidget);
      // … plus the LOUD banner, and Pay stays disabled until retry wins.
      expect(find.textContaining('Slots load nahi hue'), findsOneWidget);
      final pay = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.textContaining('Bhugtan •'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(pay.onPressed, isNull);
      expect(find.text('Dobara try karein'), findsOneWidget);
      c.dispose();
    });
  });

  group('schedule ask-once', () {
    testWidgets('once pay recaps readonly, chips only on Badlein', (
      tester,
    ) async {
      final api = _api((req) async {
        if (req.url.path.endsWith('/windows')) {
          return http.Response(
            jsonEncode({
              'windows': [
                {'start': '08:00', 'end': '08:30'},
              ],
              'date': '2026-10-07',
              'serviceable': true,
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      final c = BookingController();
      await _pumpSheet(tester, controller: c, api: api);
      await tester.tap(find.text('Aage badhein'));
      await tester.pumpAndSettle();
      // Recap, no chips re-asked …
      expect(find.textContaining('Ek baar'), findsWidgets);
      expect(find.text('Roz'), findsNothing);
      // … until Badlein opens the editor.
      await tester.tap(find.text('Badlein').first);
      await tester.pumpAndSettle();
      expect(find.text('Roz'), findsOneWidget);
      c.dispose();
    });
  });

  group('server estimate on Pay', () {
    testWidgets('sub Pay shows the server amount', (tester) async {
      final api = _api((req) async {
        if (req.url.path.endsWith('/subscriptions/estimate')) {
          return http.Response(
            jsonEncode({
              'water_bill': 5600,
              'deposit_due': 0,
              'total': 5600,
              'rate_version': 'v1',
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      final c = BookingController()
        ..setRefill(2)
        ..deliveryType = DeliveryType.daily;
      await _pumpSheet(tester, controller: c, api: api);
      await tester.tap(find.text('Aage badhein'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aage badhein'));
      await tester.pumpAndSettle();
      expect(find.text('Subscription • Rs 56'), findsOneWidget);
      c.dispose();
    });

    test('sub checkout total comes from the server estimate', () async {
      final api = _api(
        (req) async => http.Response(
          jsonEncode({
            'id': 's1',
            'first_cycle_estimate': {
              'water_bill': 5600,
              'deposit_due': 300,
              'total': 5900,
            },
          }),
          201,
        ),
      );
      final c = BookingController()
        ..setRefill(2)
        ..deliveryType = DeliveryType.daily;
      final out = await placeCheckout(
        api: api,
        controller: c,
        addressId: 'a1',
        windowStart: 'x',
        windowLabel: 'Roz',
      );
      expect(out.isSubscription, isTrue);
      expect(out.totalPaise, 5900);
      expect(out.waterPaise, 5600);
      expect(out.depositPaise, 300);
      c.dispose();
    });
  });

  group('confirm content', () {
    testWidgets('breakdown + address + UPI what-next render', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showOrderConfirm(
                  ctx,
                  result: const CheckoutResult(
                    orderId: 'o1',
                    totalPaise: 20600,
                    windowLabel: 'w',
                    isSubscription: false,
                    waterPaise: 5600,
                    depositPaise: 15000,
                    addressLabel: 'Home • H1',
                    upiPending: true,
                  ),
                  onTrackOrder: () {},
                  onOpenSubscriptions: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Paani Rs 56'), findsOneWidget);
      expect(find.textContaining('Pata: Home'), findsOneWidget);
      expect(find.textContaining('10 min me'), findsOneWidget);
    });
  });
}
