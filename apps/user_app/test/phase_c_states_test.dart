// Phase C (state audit P2) regression tests.
//
// Plugin-free: mocked transport + in-memory prefs. Covers the 409 delete
// copy, always-rendered bill rows, the honest payment-history cap note, the
// one-time first-run address prompt, and its "Not now" path.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/addresses/address_screen.dart';
import 'package:shodasha_app/features/addresses/first_run_sheet.dart';
import 'package:shodasha_app/features/booking/booking_controller.dart';
import 'package:shodasha_app/features/booking/home_screen.dart';
import 'package:shodasha_app/features/orders/bill_screen.dart';
import 'package:shodasha_app/features/orders/orders_controller.dart';
import 'package:shodasha_app/features/wallet/payment_history_screen.dart';

class _StubCatalog implements CatalogApi {
  @override
  Future<CatalogRates> fetchRates() async => const CatalogRates(
        refillPaise: 2800,
        containerPaise: 3000,
        depositPaise: 15000,
        capPaise: 300,
      );
}

Map<String, dynamic> _payment(int i) => {
      'id': 'pay_$i',
      'amount': 5600,
      'method': 'upi',
      'status': 'paid',
      'created_at': '2026-10-11T12:00:00Z',
      'jars_count': 2,
      'deposit_due': 0,
    };

Widget _home(ApiClient api, AddressController addresses, VoidCallback onAdd) {
  return MaterialApp(
    theme: buildShodashaTheme(),
    home: HomeScreen(
      controller: BookingController(catalog: _StubCatalog()),
      api: api,
      addresses: addresses,
      onOpenAddresses: onAdd,
    ),
  );
}

void main() {
  test('address delete 409 shows active-order copy, not a network failure',
      () async {
    final api = ApiClient(
      client: MockClient(
        (req) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'STATE_CONFLICT',
              'message':
                  'Address has active orders/subscriptions and cannot be '
                  'deleted',
            },
          }),
          409,
        ),
      ),
      deviceId: 'test-device',
      accessToken: 'tok',
    );
    final controller = AddressController(api: api);

    final ok = await controller.delete('a1');

    expect(ok, isFalse);
    expect(controller.errorMessage, addressStrings['deleteBlockedBody']);
  });

  testWidgets('bill always renders Cap / Previous dues / Payment rows',
      (tester) async {
    final order = Order(
      id: 'ord_1',
      state: OrderState.delivered,
      windowStart: DateTime(2026, 10, 22, 9),
      waterBillPaise: 5600,
      totalPaise: 5600,
    );

    await tester.pumpWidget(
      MaterialApp(theme: buildShodashaTheme(), home: BillScreen(order: order)),
    );

    expect(find.text('Cap'), findsOneWidget);
    expect(find.text('Previous dues'), findsOneWidget);
    expect(find.text('Payment'), findsOneWidget);
    // Absent charges render as an em dash instead of disappearing (P2-4).
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('payment history says when the 50-row server page is full', (
    tester,
  ) async {
    final api = ApiClient(
      client: MockClient(
        (req) async => http.Response(
          jsonEncode({
            'data': [for (var i = 0; i < 50; i++) _payment(i)],
          }),
          200,
        ),
      ),
      deviceId: 'test-device',
      accessToken: 'tok',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: PaymentHistoryScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    final note = find.textContaining('Showing the latest 50 payments');
    await tester.scrollUntilVisible(
      note,
      600,
      scrollable: find.byType(Scrollable),
    );
    expect(note, findsOneWidget);
  });

  testWidgets('first-run sheet opens once when addresses are empty, then '
      'persists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var addTaps = 0;
    final api = ApiClient(
      client: MockClient(
        (req) async => http.Response(jsonEncode([]), 200),
      ),
      deviceId: 'test-device',
      accessToken: 'tok',
    );
    final addresses = AddressController(api: api);
    await addresses.load();

    await tester.pumpWidget(_home(api, addresses, () => addTaps++));
    await tester.pumpAndSettle();

    expect(find.text('Set your delivery address'), findsOneWidget);
    await tester.tap(find.text('Add address'));
    await tester.pumpAndSettle();

    expect(addTaps, 1);
    expect(await shouldOfferFirstRun(), isFalse);
  });

  testWidgets('first-run "Not now" also stops future offers', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var addTaps = 0;
    final api = ApiClient(
      client: MockClient(
        (req) async => http.Response(jsonEncode([]), 200),
      ),
      deviceId: 'test-device',
      accessToken: 'tok',
    );
    final addresses = AddressController(api: api);
    await addresses.load();

    await tester.pumpWidget(_home(api, addresses, () => addTaps++));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(addTaps, 0);
    expect(await shouldOfferFirstRun(), isFalse);
    expect(find.text('Set your delivery address'), findsNothing);
  });
}
