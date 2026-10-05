// Stop shape parity: every server-selected key maps (no dropped fields).

import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/features/route/route_controller.dart';

Map<String, dynamic> wire() => {
      'id': 's1',
      'seq': 0,
      'customer_id': 'u1',
      'customer_name': 'Meena',
      'customer_phone': '+911234567890',
      'address_text': '1 Main St',
      'fulls_exp': 2,
      'empties_exp': 1,
      'total': 5600,
      'version': 1,
      'status': 'pending',
      'payment_mode': 'cod',
      'payment_status': 'unpaid',
      'order_id': 'o1',
      'order_state': 'dispatched',
      'deposit_due': 15000,
      'window_start': '2026-10-01T08:00:00Z',
      'items': [
        {'sku': 'refill', 'qty': 2}
      ],
      'instructions': 'gate band, call',
    };

void main() {
  group('RouteStop.fromJson parity', () {
    test('maps every server key', () {
      final s = RouteStop.fromJson(wire());
      expect(s.id, 's1');
      expect(s.customerName, 'Meena');
      expect(s.customerPhone, '+911234567890');
      expect(s.orderId, 'o1');
      expect(s.orderState, 'dispatched');
      expect(s.depositDuePaise, 15000);
      expect(s.windowStart, '2026-10-01T08:00:00Z');
      expect(s.items, [
        {'sku': 'refill', 'qty': 2}
      ]);
      expect(s.instructions, 'gate band, call');
      expect(s.isFailed, isFalse);
    });

    test('missing keys fall back honestly', () {
      final s = RouteStop.fromJson({'id': 's9'});
      expect(s.items, isEmpty);
      expect(s.instructions, isEmpty);
      expect(s.customerPhone, isEmpty);
      expect(s.windowStart, isEmpty);
    });

    test('failed stops read as failed, not pending', () {
      final s = RouteStop.fromJson({...wire(), 'status': 'failed'});
      expect(s.isFailed, isTrue);
      expect(s.isDone, isFalse);
    });

    test('itemsOf rejects non-lists', () {
      expect(RouteStop.itemsOf('nope'), isEmpty);
      expect(RouteStop.itemsOf(null), isEmpty);
    });
  });
}
