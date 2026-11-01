import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/features/orders/order_card.dart';
import 'package:shodasha_donor/features/orders/orders_controller.dart';
import 'package:shodasha_donor/shared/ui/app_button.dart';
import 'package:shodasha_donor/shared/ui/app_card.dart';

void main() {
  testWidgets('donor card maps a live order and exposes Track, not delivery', (
    tester,
  ) async {
    var tracked = false;
    var billed = false;
    final order = _order(state: OrderState.assigned);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DonorOrderCard(
            order: order,
            onTrack: () => tracked = true,
            onBill: () => billed = true,
          ),
        ),
      ),
    );

    expect(find.text('2 × 20L refill'), findsOneWidget);
    expect(find.text('Rider assigned'), findsOneWidget);
    expect(find.text('Track order'), findsOneWidget);
    expect(find.text('View bill'), findsNothing);
    expect(find.textContaining('DELIVERY PIN'), findsNothing);

    await tester.tap(find.text('Track order'));
    expect(tracked, isTrue);
    expect(billed, isFalse);
  });

  testWidgets('delivered order shows View bill and the server PoD only', (
    tester,
  ) async {
    var tracked = false;
    var billed = false;
    final order = _order(
      state: OrderState.delivered,
      deliveryOtp: '4821',
      paymentStatus: 'paid_upi',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DonorOrderCard(
            order: order,
            onTrack: () => tracked = true,
            onBill: () => billed = true,
          ),
        ),
      ),
    );

    expect(find.text('Delivered'), findsOneWidget);
    expect(find.text('View bill'), findsOneWidget);
    expect(find.text('Track order'), findsNothing);
    expect(find.textContaining('DELIVERY PIN'), findsNothing);

    await tester.tap(find.text('View bill'));
    expect(billed, isTrue);
    expect(tracked, isFalse);
  });

  testWidgets('donor card truncates long UUID to 8 uppercase chars', (
    tester,
  ) async {
    final order = _order(
      state: OrderState.assigned,
      id: '2236358550c8425abd9a23f1af39839e',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DonorOrderCard(
            order: order,
            onTrack: () {},
            onBill: () {},
          ),
        ),
      ),
    );

    expect(find.text('#22363585'), findsOneWidget);
    expect(find.text('#2236358550c8425abd9a23f1af39839e'), findsNothing);
  });

  testWidgets('entire card surface responds to tap (Track active, Bill closed)', (
    tester,
  ) async {
    var tracked = false;
    var billed = false;

    // Active order card tap -> onTrack
    final activeOrder = _order(state: OrderState.assigned);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DonorOrderCard(
            order: activeOrder,
            onTrack: () => tracked = true,
            onBill: () => billed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppCard));
    expect(tracked, isTrue);
    expect(billed, isFalse);

    // Reset flags and test closed order card tap -> onBill
    tracked = false;
    billed = false;
    final closedOrder = _order(state: OrderState.delivered);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DonorOrderCard(
            order: closedOrder,
            onTrack: () => tracked = true,
            onBill: () => billed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppCard));
    expect(billed, isTrue);
    expect(tracked, isFalse);
  });

  testWidgets('closed order View bill uses AppButtonKind.secondary', (
    tester,
  ) async {
    final order = _order(state: OrderState.delivered);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DonorOrderCard(
            order: order,
            onTrack: () {},
            onBill: () {},
          ),
        ),
      ),
    );

    final billButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'View bill'),
    );
    expect(billButton.kind, AppButtonKind.secondary);
  });

  testWidgets('renders fallback 20L Jar Delivery when itemSummary is empty', (
    tester,
  ) async {
    final order = Order(
      id: 'SHD-999',
      state: OrderState.assigned,
      windowStart: DateTime(2026, 10, 23, 8),
      windowEnd: DateTime(2026, 10, 23, 11),
      itemSummary: '',
      addressLabel: 'Home · Arera Colony',
      totalPaise: 5600,
      refillQty: 0,
      containerQty: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DonorOrderCard(
            order: order,
            onTrack: () {},
            onBill: () {},
          ),
        ),
      ),
    );

    expect(find.text('20L Jar Delivery'), findsOneWidget);
    expect(find.text('Water order'), findsNothing);
  });
}

Order _order({
  required OrderState state,
  String id = 'SHD-1001',
  String? deliveryOtp,
  String paymentStatus = 'unpaid',
}) {
  return Order(
    id: id,
    state: state,
    windowStart: DateTime(2026, 10, 23, 8),
    windowEnd: DateTime(2026, 10, 23, 11),
    itemSummary: '2 x 20L Refill',
    addressLabel: 'Home · Arera Colony',
    totalPaise: 5600,
    refillQty: 2,
    containerQty: 0,
    paymentMode: 'upi',
    paymentStatus: paymentStatus,
    deliveryOtp: deliveryOtp,
  );
}
