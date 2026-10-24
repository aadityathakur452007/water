import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/features/orders/order_card.dart';
import 'package:shodasha_donor/features/orders/orders_controller.dart';

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
}

Order _order({
  required OrderState state,
  String? deliveryOtp,
  String paymentStatus = 'unpaid',
}) {
  return Order(
    id: 'SHD-1001',
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
