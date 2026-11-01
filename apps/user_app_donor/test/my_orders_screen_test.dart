import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/core/theme.dart';
import 'package:shodasha_donor/features/orders/my_orders_screen.dart';
import 'package:shodasha_donor/features/orders/orders_controller.dart';

void main() {
  testWidgets(
    'orders screen omits Active section when user has only past orders',
    (tester) async {
      final repo = StubOrdersRepository([
        Order(
          id: 'past-order-1',
          state: OrderState.delivered,
          windowStart: DateTime(2026, 10, 20, 9),
          itemSummary: '2 × 20L refill',
          totalPaise: 5600,
        ),
      ]);
      final controller = OrdersController(repo: repo);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: DonorOrdersScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Past orders'), findsOneWidget);
      expect(find.text('Active'), findsNothing);
      expect(find.text('No active deliveries'), findsNothing);
      expect(find.text('2 × 20L refill'), findsOneWidget);
    },
  );

  testWidgets(
    'orders screen shows Active and Past sections when both exist',
    (tester) async {
      final repo = StubOrdersRepository([
        Order(
          id: 'active-order-1',
          state: OrderState.dispatched,
          windowStart: DateTime(2026, 10, 31, 10),
          itemSummary: '1 × 20L refill',
          totalPaise: 2800,
        ),
        Order(
          id: 'past-order-2',
          state: OrderState.delivered,
          windowStart: DateTime(2026, 10, 20, 9),
          itemSummary: '2 × 20L refill',
          totalPaise: 5600,
        ),
      ]);
      final controller = OrdersController(repo: repo);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: DonorOrdersScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Past orders'), findsOneWidget);
      expect(find.text('1 × 20L refill'), findsOneWidget);
      expect(find.text('2 × 20L refill'), findsOneWidget);
    },
  );

  testWidgets(
    'orders screen shows clean stale banner on refresh connection issue',
    (tester) async {
      final repo = _ErrorOnRefreshOrdersRepository([
        Order(
          id: 'order-1',
          state: OrderState.delivered,
          windowStart: DateTime(2026, 10, 20, 9),
          itemSummary: '1 × 20L refill',
        ),
      ]);
      final controller = OrdersController(repo: repo);
      await controller.load();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: DonorOrdersScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger refresh which fails with server error
      await controller.refresh();
      await tester.pumpAndSettle();

      expect(
        find.text('Connection issue · Showing saved orders'),
        findsOneWidget,
      );
      expect(
        find.text('Server problem — showing the orders already loaded.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'orders screen shows empty state with Book water CTA when zero orders',
    (tester) async {
      var startedOrder = false;
      final repo = StubOrdersRepository([]);
      final controller = OrdersController(repo: repo);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: DonorOrdersScreen(
            controller: controller,
            onStartOrder: () => startedOrder = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No orders yet'), findsOneWidget);
      expect(find.text('Book water'), findsOneWidget);

      await tester.tap(find.text('Book water'));
      expect(startedOrder, isTrue);
    },
  );
}

class _ErrorOnRefreshOrdersRepository extends StubOrdersRepository {
  _ErrorOnRefreshOrdersRepository(super.seed);
  int _loads = 0;

  @override
  Future<OrdersPage> fetchOrders({String? cursor}) async {
    _loads++;
    if (_loads > 1) {
      throw ApiException(
        code: 'INTERNAL',
        message: 'Database error',
        statusCode: 500,
      );
    }
    return super.fetchOrders(cursor: cursor);
  }
}
