import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/core/theme.dart';
import 'package:shodasha_donor/features/addresses/address_screen.dart';
import 'package:shodasha_donor/features/booking/booking_controller.dart';
import 'package:shodasha_donor/features/home/customer_home_screen.dart';
import 'package:shodasha_donor/features/orders/orders_controller.dart';
import 'package:shodasha_donor/shared/ui/status_pill.dart';

void main() {
  testWidgets(
    'home tab renders unified mode cards, trust pill, and updated copy',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = _FakeHomeApi();
      final booking = BookingController(
        initialRates: const CatalogRates(
          refillPaise: 2800,
          containerPaise: 3000,
          depositPaise: 15000,
          capPaise: 300,
        ),
      );
      final addresses = AddressController(api: api);
      final repo = StubOrdersRepository();
      final orders = OrdersController(repo: repo);

      bool instantTapped = false;
      bool subscribeTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: Scaffold(
            body: DonorHomeTab(
              api: api,
              booking: booking,
              addresses: addresses,
              orders: orders,
              onInstantOrder: () => instantTapped = true,
              onSubscribe: () => subscribeTapped = true,
              onOpenAddresses: () {},
              onOpenNotifications: () {},
              onOpenProfile: () {},
              onOpenSupport: () {},
              onOpenCart: () {},
              onOrderProduct:
                  ({required int refill, required int container}) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify StatusPill RO + UV
      expect(find.widgetWithText(StatusPill, 'RO + UV'), findsOneWidget);

      // 2. Verify ModeSelectionCards
      expect(find.text('Instant order'), findsOneWidget);
      expect(find.text('Subscribe'), findsOneWidget);
      expect(find.text('Pick a 30-min slot'), findsOneWidget);
      expect(find.text('Set a repeat plan'), findsOneWidget);

      await tester.tap(find.text('Instant order'));
      await tester.pump();
      expect(instantTapped, isTrue);

      await tester.tap(find.text('Subscribe'));
      await tester.pump();
      expect(subscribeTapped, isTrue);

      // 3. Verify Featured Products updated copy
      expect(
        find.text('Exchange empty jar at delivery · RO + UV purified'),
        findsOneWidget,
      );
      expect(find.text('Includes ₹150 refundable jar deposit'), findsOneWidget);

      // 4. Scroll down to verify Purity Card updated copy
      await tester.scrollUntilVisible(find.text('On WhatsApp'), 200);
      expect(find.text('On WhatsApp'), findsOneWidget);

      // 5. Scroll down to verify Support Card updated copy
      await tester.scrollUntilVisible(
        find.text('Call or WhatsApp Bhopal support directly'),
        200,
      );
      expect(
        find.text('Call or WhatsApp Bhopal support directly'),
        findsOneWidget,
      );
    },
  );
}

class _FakeHomeApi extends ApiClient {
  _FakeHomeApi()
    : super(
        baseUrl: 'http://127.0.0.1/v1',
        deviceId: 'test-device',
        accessTokenGetter: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> catalog({bool allowStale = false}) async => {
    'skus': [
      {'id': 'refill', 'price_paise': 2800},
      {'id': 'container', 'price_paise': 3000},
    ],
    'deposit_per_jar': 15000,
    'cap_charge': 300,
  };

  @override
  Future<List<dynamic>> listAddresses() async => const [];
}
