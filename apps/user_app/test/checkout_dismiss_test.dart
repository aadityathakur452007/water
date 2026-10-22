// P2-3 regression — checkout is a task, not a swipe-away sheet.
//
// Law: a drag must never dismiss checkout. While payment is in flight, back
// and barrier taps must ask before leaving (the order may already exist and
// the payment may still settle). Outside payment, closing stays one tap.
// Plugin-free: MockClient holds POST /orders open to keep the sheet paying;
// pumps are bounded because the 12s request timeout must not fire mid-test.

import 'dart:async';
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

Map<String, dynamic> _order() => {
      'id': 'o1',
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

ApiClient _api({Future<void>? ordersGate}) => ApiClient(
      client: MockClient((req) async {
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
          if (ordersGate != null) await ordersGate;
          return _json({'order': _order()}, 201);
        }
        if (req.method == 'POST' && path.endsWith('/payments/upi-intent')) {
          return _json({'detail': 'gateway down'}, 400);
        }
        return _json({}, 404);
      }),
      accessToken: 't',
      deviceId: 'd',
    );

Future<BookingController> _openSheet(
  WidgetTester tester,
  ApiClient api,
) async {
  final c = BookingController()..setRefill(1);
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
              onDone: (_) {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return c;
}

/// One frame + a short settle for route/dialog transitions. Never
/// pumpAndSettle while a payment request is in flight: it advances fake time
/// past the 12s ApiClient timeout and turns the sheet into an error state.
Future<void> _tick(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets('a drag never dismisses checkout; a tap does when idle',
      (tester) async {
    final c = await _openSheet(tester, _api());

    // Drag the header down hard — no handle, no dismiss.
    await tester.drag(find.text('Address'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Address'), findsOneWidget);

    // Outside payment the barrier is still a one-tap close.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Address'), findsNothing);
    c.dispose();
  });

  testWidgets('while paying, barrier and back ask; Stay keeps the sheet',
      (tester) async {
    final gate = Completer<void>();
    final c = await _openSheet(tester, _api(ordersGate: gate.future));

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('PAY'));
    await tester.pump();

    // Order POST is held open: payment is in flight.
    expect(find.text('Placing your order…'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);

    // Barrier tap → warning, not a dismissal.
    await tester.tapAt(const Offset(10, 10));
    await _tick(tester);
    expect(find.text('Payment still processing'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);

    await tester.tap(find.text('Stay'));
    await _tick(tester);
    expect(find.text('Payment still processing'), findsNothing);
    expect(find.text('Address'), findsOneWidget);

    // System back → same warning.
    await tester.binding.handlePopRoute();
    await _tick(tester);
    expect(find.text('Payment still processing'), findsOneWidget);

    // Leave really leaves, without waiting for the in-flight POST. The
    // dialog exits first; the sheet pop runs in the next frame.
    await tester.tap(find.text('Leave'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Address'), findsNothing);
    expect(find.text('Payment still processing'), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump();
    c.dispose();
  });
}
