import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/features/orders/orders_controller.dart';
import 'package:shodasha_donor/features/home/customer_home_screen.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/features/addresses/address_screen.dart';
import 'package:shodasha_donor/features/booking/booking_controller.dart';

void main() {
  group('OrdersController.reorderCandidate', () {
    test('returns null when allOrders is empty', () {
      final repo = StubOrdersRepository();
      final controller = OrdersController(repo: repo);
      expect(controller.reorderCandidate, isNull);
    });

    test('returns null when orders have no SKU mix (legacy)', () {
      final repo = StubOrdersRepository([
        Order(
          id: 'ord-1',
          state: OrderState.delivered,
          windowStart: DateTime.now(),
          refillQty: 0,
          containerQty: 0,
        ),
      ]);
      final controller = OrdersController(repo: repo);
      // seed into repository doesn't populate _all until load() is called
      expect(controller.reorderCandidate, isNull);
    });

    test('returns first canReorder order once loaded', () async {
      final repo = StubOrdersRepository([
        Order(
          id: 'ord-legacy',
          state: OrderState.delivered,
          windowStart: DateTime.now(),
          refillQty: 0,
          containerQty: 0,
        ),
        Order(
          id: 'ord-reorderable',
          state: OrderState.delivered,
          windowStart: DateTime.now(),
          refillQty: 2,
          containerQty: 1,
          itemSummary: '2 refill + 1 container',
        ),
      ]);
      final controller = OrdersController(repo: repo);
      await controller.load();
      expect(controller.reorderCandidate, isNotNull);
      expect(controller.reorderCandidate!.id, 'ord-reorderable');
      expect(controller.reorderCandidate!.refillQty, 2);
      expect(controller.reorderCandidate!.containerQty, 1);
    });
  });

  group('DonorHomeTab QuickReorderCard widget', () {
    testWidgets('renders QuickReorderCard when candidate exists and triggers onOrderProduct', (tester) async {
      final repo = StubOrdersRepository([
        Order(
          id: 'ord-101',
          state: OrderState.delivered,
          windowStart: DateTime.now(),
          refillQty: 2,
          containerQty: 0,
          itemSummary: '2 refill',
        ),
      ]);
      final orders = OrdersController(repo: repo);
      await orders.load();

      int orderedRefill = 0;
      int orderedContainer = 0;

      final booking = BookingController(
        initialRates: const CatalogRates(
          refillPaise: 2800,
          containerPaise: 3000,
          depositPaise: 15000,
          capPaise: 300,
        ),
      );

      final api = _DummyApi();
      final addresses = AddressController(api: api);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DonorHomeTab(
              api: api,
              booking: booking,
              addresses: addresses,
              orders: orders,
              onInstantOrder: () {},
              onSubscribe: () {},
              onOpenAddresses: () {},
              onOpenNotifications: () {},
              onOpenProfile: () {},
              onOpenSupport: () {},
              onOpenCart: () {},
              onOrderProduct: ({required int refill, required int container}) {
                orderedRefill = refill;
                orderedContainer = container;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reorder last delivery'), findsOneWidget);
      expect(find.text('2 refill'), findsOneWidget);
      expect(find.text('Reorder'), findsOneWidget);

      await tester.tap(find.text('Reorder'));
      await tester.pumpAndSettle();

      expect(orderedRefill, 2);
      expect(orderedContainer, 0);
    });

    testWidgets('does not render QuickReorderCard when orders is null or no candidate', (tester) async {
      final repo = StubOrdersRepository([]);
      final orders = OrdersController(repo: repo);
      await orders.load();

      final booking = BookingController(
        initialRates: const CatalogRates(
          refillPaise: 2800,
          containerPaise: 3000,
          depositPaise: 15000,
          capPaise: 300,
        ),
      );

      final api = _DummyApi();
      final addresses = AddressController(api: api);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DonorHomeTab(
              api: api,
              booking: booking,
              addresses: addresses,
              orders: orders,
              onInstantOrder: () {},
              onSubscribe: () {},
              onOpenAddresses: () {},
              onOpenNotifications: () {},
              onOpenProfile: () {},
              onOpenSupport: () {},
              onOpenCart: () {},
              onOrderProduct: ({required int refill, required int container}) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reorder last delivery'), findsNothing);
    });
  });
}

class _DummyApi extends ApiClient {
  _DummyApi()
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
