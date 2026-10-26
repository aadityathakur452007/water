// 005-home-ux — checkout payload seams (pure Dart, no widgets).
import 'package:flutter_test/flutter_test.dart';

import 'package:shodasha_app/features/booking/booking_controller.dart';
import 'package:shodasha_app/features/orders/orders_controller.dart'
    show Order, OrderState;

void main() {
  group('delivery type wire mapping', () {
    test('once maps to empty schedule (no subscription)', () {
      expect(scheduleTypeOf(DeliveryType.once), '');
    });

    test('recurring maps to contract schedule_type values', () {
      expect(scheduleTypeOf(DeliveryType.daily), 'daily');
      expect(scheduleTypeOf(DeliveryType.alternate), 'alternate');
      expect(scheduleTypeOf(DeliveryType.weekly), 'weekly');
      expect(scheduleTypeOf(DeliveryType.custom), 'custom');
    });
  });

  group('sku mix', () {
    test('dominant SKU wins', () {
      expect(skuMixOf(refill: 3, container: 1), 'refill');
      expect(skuMixOf(refill: 1, container: 3), 'container');
    });

    test('ties go refill (cheaper default)', () {
      expect(skuMixOf(refill: 2, container: 2), 'refill');
    });
  });

  group('order items payload', () {
    test('skips zero lines, keeps wire ids', () {
      expect(
        orderItemsOf(refill: 2, container: 0),
        [
          {'sku': 'refill', 'qty': 2}
        ],
      );
      expect(
        orderItemsOf(refill: 0, container: 1),
        [
          {'sku': 'container', 'qty': 1}
        ],
      );
      expect(
        orderItemsOf(refill: 2, container: 3),
        [
          {'sku': 'refill', 'qty': 2},
          {'sku': 'container', 'qty': 3},
        ],
      );
    });

    test('empty lines produce empty list (callers gate on canBook)', () {
      expect(orderItemsOf(refill: 0, container: 0), isEmpty);
    });
  });

  group('controller buy-path state', () {
    test('delivery type defaults to once', () {
      final c = BookingController();
      expect(c.deliveryType, DeliveryType.once);
      c.dispose();
    });
  });

  group('repeat history gates (006-auth-flow)', () {
    Order orderOf({int refill = 0, int container = 0}) => Order(
          id: 'o1',
          state: OrderState.delivered,
          windowStart: DateTime.utc(2026, 10, 1, 9),
          refillQty: refill,
          containerQty: container,
        );

    test('reorder hidden when mix unknown, shown when known', () {
      expect(orderOf().canReorder, isFalse);
      expect(orderOf(refill: 2).canReorder, isTrue);
      expect(orderOf(container: 1).canReorder, isTrue);
    });

    test('bulk badge at N>=6 (matches confirm band)', () {
      expect(orderOf(refill: 3, container: 2).isBulk, isFalse);
      expect(orderOf(refill: 4, container: 2).isBulk, isTrue);
    });
  });
}
