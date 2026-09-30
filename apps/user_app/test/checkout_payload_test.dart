// 005-home-ux — checkout payload seams (pure Dart, no widgets).
import 'package:flutter_test/flutter_test.dart';

import 'package:shodasha_app/features/booking/booking_controller.dart';

void main() {
  group('delivery type wire mapping', () {
    test('once maps to empty schedule (no subscription)', () {
      expect(scheduleTypeOf(DeliveryType.once), '');
    });

    test('recurring maps to contract schedule_type values', () {
      expect(scheduleTypeOf(DeliveryType.daily), 'daily');
      expect(scheduleTypeOf(DeliveryType.alternate), 'alternate');
      expect(scheduleTypeOf(DeliveryType.weekly), 'weekly');
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
}
