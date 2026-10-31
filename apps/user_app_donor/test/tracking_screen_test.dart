import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/theme.dart';
import 'package:shodasha_donor/features/orders/orders_controller.dart';
import 'package:shodasha_donor/features/orders/tracking_screen.dart';

void main() {
  testWidgets('renders Next stop is yours when stopsAhead is 0', (tester) async {
    final order = _buildOrder(
      id: 'ord-next',
      state: OrderState.dispatched,
      stopsAhead: 0,
    );
    final repo = StubOrdersRepository([order]);
    final controller = OrdersController(repo: repo);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: TrackingScreen(controller: controller, orderId: 'ord-next'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Next stop is yours'), findsOneWidget);
    expect(
      find.text('Arriving now · Please keep your empty jar ready'),
      findsOneWidget,
    );
    expect(find.text('Your stop is next!'), findsNothing);
  });

  testWidgets('renders stops away banner and estimated arrival when stopsAhead > 0', (
    tester,
  ) async {
    final order = _buildOrder(
      id: 'ord-2stops',
      state: OrderState.dispatched,
      stopsAhead: 2,
    );
    final repo = StubOrdersRepository([order]);
    final controller = OrdersController(repo: repo);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: TrackingScreen(controller: controller, orderId: 'ord-2stops'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Driver is 2 stops away'), findsOneWidget);
    expect(
      find.text('Estimated arrival in ~20–30 mins · Keep empty jar ready'),
      findsOneWidget,
    );
  });

  testWidgets('renders sanitized delivery code verified status when used', (
    tester,
  ) async {
    final order = _buildOrder(
      id: 'ord-used',
      state: OrderState.delivered,
      deliveryCodeState: 'used',
    );
    final repo = StubOrdersRepository([order]);
    final controller = OrdersController(repo: repo);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: TrackingScreen(controller: controller, orderId: 'ord-used'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delivery complete · Code verified'), findsOneWidget);
    expect(find.text('Delivery complete — code used.'), findsNothing);
  });

  testWidgets('renders clean locked code notice after wrong attempts', (
    tester,
  ) async {
    final order = _buildOrder(
      id: 'ord-locked',
      state: OrderState.dispatched,
      deliveryCodeState: 'locked',
    );
    final repo = StubOrdersRepository([order]);
    final controller = OrdersController(repo: repo);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: TrackingScreen(controller: controller, orderId: 'ord-locked'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Too many wrong attempts'), findsOneWidget);
    expect(
      find.text('Code locked after wrong attempts · Request a new code'),
      findsOneWidget,
    );
  });
}

Order _buildOrder({
  required String id,
  required OrderState state,
  int stopsAhead = 0,
  String deliveryCodeState = 'active',
}) {
  return Order(
    id: id,
    state: state,
    windowStart: DateTime(2026, 10, 31, 9),
    windowEnd: DateTime(2026, 10, 31, 9, 30),
    itemSummary: '2 × 20L Refill',
    addressLabel: 'Arera Colony',
    totalPaise: 5600,
    stopsAhead: stopsAhead,
    riderName: 'Vikram Singh',
    riderPhone: '+919876543210',
    deliveryOtp: '654321',
    deliveryCodeState: deliveryCodeState,
  );
}
