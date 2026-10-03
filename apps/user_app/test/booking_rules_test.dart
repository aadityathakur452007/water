// F3 — Booking rules unit tests (pure controller math + gates).
// Run: flutter test test/booking_rules_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_app/features/booking/booking_controller.dart';

BookingController _c() => BookingController();

void main() {
  group('quote math (paise integer)', () {
    // 014: refill never deposits.
    test('2 refill + 1 empty: 5600 water + 0 deposit', () {
      expect(
        computeQuoteTotalPaise(refill: 2, container: 0, empties: 1),
        2 * 2800,
      );
    });

    test('1 container first time: 3000 + 15000 deposit', () {
      expect(
        computeQuoteTotalPaise(refill: 0, container: 1, empties: 0),
        3000 + 15000,
      );
    });

    test('deposit waived when wallet holds it', () {
      expect(
        computeQuoteTotalPaise(
            refill: 0, container: 1, empties: 0, depositPaidPaise: 15000),
        3000,
      );
    });

    test('container SKU bills at 3000', () {
      expect(
        computeWaterBillPaise(refill: 0, container: 2),
        6000,
      );
    });

    test('cap-missing adds 300 per cap', () {
      expect(
        computeQuoteTotalPaise(
          refill: 1,
          container: 0,
          empties: 1,
          capsMissing: 2,
        ),
        2800 + 600,
      );
    });

    test('full empties → zero deposit', () {
      expect(
        computeDepositDuePaise(container: 3, empties: 3),
        0,
      );
    });
  });

  group('stepper gates', () {
    test('N=0 → BOOK NOW disabled', () {
      expect(_c().canBook, isFalse);
    });

    test('N>=1 → BOOK NOW enabled', () {
      final c = _c()..setRefill(2);
      expect(c.canBook, isTrue);
    });

    test('E clamps to N live', () {
      final c = _c()
        ..setRefill(2)
        ..setEmpties(9);
      expect(c.emptiesQty, 2);
    });

    test('steppers clamp 0–10', () {
      final c = _c()..setRefill(99);
      expect(c.refillQty, 10);
    });

    test('N 6–10 → confirm dialog flag', () {
      final c = _c()..setRefill(6);
      expect(c.needsBulkConfirm, isTrue);
      expect(c.isTanker, isFalse);
    });

    test('N 5 → no dialog', () {
      final c = _c()..setRefill(5);
      expect(c.needsBulkConfirm, isFalse);
    });

    test('N>10 → tanker, never an order', () {
      final c = _c()
        ..setRefill(10)
        ..setContainer(5);
      expect(c.totalJars, 15);
      expect(c.isTanker, isTrue);
    });
  });

  group('COD gates (tunables)', () {
    test('quote > Rs 2000 → COD off', () {
      // 40 refill jars (Rs 1,120) alone stays under cap — callers only reach
      // that via prices; pass an intentionally over-cap total (contract).
      expect(
        isCodAllowed(
          quoteTotalPaise: 200001,
          duesPaise: 0,
          heldJars: 0,
        ),
        isFalse,
      );
    });

    test('held > 3 → COD off', () {
      expect(
        isCodAllowed(quoteTotalPaise: 2800, duesPaise: 0, heldJars: 4),
        isFalse,
      );
    });

    test('dues over cap → COD off', () {
      expect(
        isCodAllowed(
          quoteTotalPaise: 2800,
          duesPaise: 200001,
          heldJars: 0,
        ),
        isFalse,
      );
    });

    test('small quote, clean ledger → COD on', () {
      expect(
        isCodAllowed(quoteTotalPaise: 5600, duesPaise: 0, heldJars: 1),
        isTrue,
      );
    });
  });

  group('quote freeze', () {
    test('older than 15 min → stale', () {
      final now = DateTime.utc(2026, 9, 29, 10, 0);
      expect(
        isQuoteStale(
          quoteCreatedAtUtc: now.subtract(const Duration(minutes: 16)),
          frozenHash: '2|0|1|0',
          currentHash: '2|0|1|0',
          nowUtc: now,
        ),
        isTrue,
      );
    });

    test('changed inputs → stale even when fresh', () {
      final now = DateTime.utc(2026, 9, 29, 10, 0);
      expect(
        isQuoteStale(
          quoteCreatedAtUtc: now,
          frozenHash: '2|0|1|0',
          currentHash: '3|0|1|0',
          nowUtc: now,
        ),
        isTrue,
      );
    });

    test('silent re-quote refreezes', () {
      final c = _c()..setRefill(2);
      c.freezeQuote(DateTime.utc(2026, 9, 29, 10, 0));
      c.setRefill(3);
      final did = c.silentRequoteIfNeeded(
        DateTime.utc(2026, 9, 29, 10, 1),
      );
      expect(did, isTrue);
      expect(c.frozenHash, c.currentHash);
    });
  });

  group('windows + idempotency', () {
    // 014: all days water — Sundays are serviceable now.
    test('Saturday → Sunday (no Sunday skip)', () {
      final next = nextServiceableDay(DateTime(2026, 10, 3));
      expect(next, DateTime(2026, 10, 4));
    });

    test('holiday is skipped', () {
      final next = nextServiceableDay(
        DateTime(2026, 10, 2),
        holidays: {DateTime(2026, 10, 3)},
      );
      expect(next, DateTime(2026, 10, 4));
    });

    test('idempotency minted once, reused on retry', () {
      final c = _c();
      final first = c.ensureIdempotencyKey();
      expect(first.isNotEmpty, isTrue);
      expect(c.ensureIdempotencyKey(), first);
    });

    test('two sheets → two keys', () {
      final a = _c()..ensureIdempotencyKey();
      final b = _c()..ensureIdempotencyKey();
      expect(a.idempotencyKey, isNot(b.idempotencyKey));
    });
  });
}
