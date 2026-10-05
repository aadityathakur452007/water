// PoD offline payload + outbox shape (pure logic, no plugins).

import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/features/stops/stops_controller.dart';
import 'package:vendor_app/features/sync/sync_controller.dart';

void main() {
  group('buildPodBody', () {
    test('builds live-shaped body in paise', () {
      final b = buildPodBody(
        deliveryOtp: '482910',
        emptiesCount: 1,
        cashPaise: 5600,
      );
      expect(b['delivery_otp'], '482910');
      expect(b['empties_count'], 1);
      expect(b['cash'], 5600);
      expect(b['seal_ok'], isTrue);
      expect(b.containsKey('lat'), isFalse);
    });

    test('carries GPS when present', () {
      final b = buildPodBody(
        deliveryOtp: '482910',
        emptiesCount: 0,
        cashPaise: 0,
        lat: 12.9,
        lng: 77.5,
      );
      expect(b['lat'], 12.9);
      expect(b['lng'], 77.5);
    });
  });

  group('QueuedTriple pod items', () {
    test('toSyncItem flags pod + keeps live shape', () {
      const q = QueuedTriple(
        stopId: 's1',
        triple: {},
        idempotencyKey: 'k1',
        queuedAtIso: 't',
        pod: {'delivery_otp': '482910', 'empties_count': 1},
      );
      final item = q.toSyncItem();
      expect(item['pod'], isTrue);
      expect(item['delivery_otp'], '482910');
      expect(item['stop_id'], 's1');
    });

    test('triple items stay unflagged (backward compatible)', () {
      const q = QueuedTriple(
        stopId: 's1',
        triple: {'fulls_given': 2},
        idempotencyKey: 'k1',
        queuedAtIso: 't',
      );
      expect(q.toSyncItem().containsKey('pod'), isFalse);
    });

    test('pod round-trips through storage JSON', () {
      const q = QueuedTriple(
        stopId: 's1',
        triple: {},
        idempotencyKey: 'k1',
        queuedAtIso: 't',
        cashAmountPaise: 5600,
        pod: {'delivery_otp': '482910'},
      );
      final back = QueuedTriple.fromJson(q.toJson());
      expect(back.pod['delivery_otp'], '482910');
      expect(back.cashAmountPaise, 5600);
      // Pre-pod rows lack the key entirely — still parse.
      final legacy = QueuedTriple.fromJson({
        'stop_id': 's1',
        'triple': {'fulls_given': 2},
        'idempotency_key': 'k1',
        'queued_at': 't',
      });
      expect(legacy.pod, isEmpty);
    });
  });
}
