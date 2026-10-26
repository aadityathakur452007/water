// Booking rules unit tests (pure controller math + gates).
// Rates are injected explicitly — the app never falls back to local prices.

import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_app/features/booking/booking_controller.dart';

const _rates = CatalogRates(
  refillPaise: 2800,
  containerPaise: 3000,
  depositPaise: 15000,
  capPaise: 300,
);

BookingController _c() => BookingController(initialRates: _rates);

void main() {
  group('quote math (paise integer, server rates)', () {
    test('2 refill + 1 empty: 5600 water + 0 deposit', () {
      expect(
        computeQuoteTotalPaise(
          refill: 2,
          container: 0,
          empties: 1,
          rates: _rates,
        ),
        2 * 2800,
      );
    });

    test('1 container first time: 3000 + 15000 deposit', () {
      expect(
        computeQuoteTotalPaise(
          refill: 0,
          container: 1,
          empties: 0,
          rates: _rates,
        ),
        3000 + 15000,
      );
    });

    test('deposit waived when wallet holds it', () {
      expect(
        computeQuoteTotalPaise(
          refill: 0,
          container: 1,
          empties: 0,
          rates: _rates,
          depositPaidPaise: 15000,
        ),
        3000,
      );
    });

    test('container SKU bills at 3000', () {
      expect(
        computeWaterBillPaise(refill: 0, container: 2, rates: _rates),
        6000,
      );
    });

    test('cap-missing adds 300 per cap', () {
      expect(
        computeQuoteTotalPaise(
          refill: 1,
          container: 0,
          empties: 1,
          rates: _rates,
          capsMissing: 2,
        ),
        2800 + 600,
      );
    });

    test('full empties → zero deposit', () {
      expect(
        computeDepositDuePaise(
          container: 3,
          empties: 3,
          rates: _rates,
        ),
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
      c.dispose();
    });

    test('E clamps to N live', () {
      final c = _c()
        ..setRefill(2)
        ..setEmpties(9);
      expect(c.emptiesQty, 2);
      c.dispose();
    });

    test('steppers clamp 0–10', () {
      final c = _c()..setRefill(99);
      expect(c.refillQty, 10);
      c.dispose();
    });

    test('N 6–10 → confirm dialog flag', () {
      final c = _c()..setRefill(6);
      expect(c.needsBulkConfirm, isTrue);
      expect(c.isTanker, isFalse);
      c.dispose();
    });

    test('N 5 → no dialog', () {
      final c = _c()..setRefill(5);
      expect(c.needsBulkConfirm, isFalse);
      c.dispose();
    });

    test('N>10 → tanker, never an order', () {
      final c = _c()
        ..setRefill(10)
        ..setContainer(5);
      expect(c.totalJars, 15);
      expect(c.isTanker, isTrue);
      c.dispose();
    });
  });

  group('COD gates (tunables)', () {
    test('quote > Rs 2000 → COD off', () {
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
      c.dispose();
    });
  });

  group('windows + idempotency', () {
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
      c.dispose();
    });

    test('two sheets → two keys', () {
      final a = _c()..ensureIdempotencyKey();
      final b = _c()..ensureIdempotencyKey();
      expect(a.idempotencyKey, isNot(b.idempotencyKey));
      a.dispose();
      b.dispose();
    });

    test('refreshIdempotencyKey forces a brand new key', () {
      final c = _c();
      final first = c.ensureIdempotencyKey();
      final second = c.refreshIdempotencyKey();
      expect(second, isNot(first));
      expect(c.idempotencyKey, second);
      c.dispose();
    });

    test('resetBookingSession clears key and resets quantities', () {
      final c = _c();
      c.setRefill(2);
      c.setContainer(1);
      c.ensureIdempotencyKey();
      expect(c.idempotencyKey, isNotNull);
      expect(c.totalJars, 3);

      c.resetBookingSession();
      expect(c.idempotencyKey, isNull);
      expect(c.totalJars, 0);
      expect(c.refillQty, 0);
      expect(c.containerQty, 0);
      c.dispose();
    });
  });

  group('payment mode', () {
    test('switching mode refreshes the idempotency key', () {
      final c = _c();
      final first = c.ensureIdempotencyKey();
      c.paymentMode = PaymentMode.cod;
      expect(c.idempotencyKey, isNot(first));
      c.dispose();
    });

    test('COD requires a server quote total', () {
      final c = _c();
      expect(c.codAllowed, isFalse);
      c.dispose();
    });
  });

  group('server quote', () {
    test('applyQuote stores server money verbatim', () {
      final c = _c();
      c.applyQuote({
        'water_bill': 5600,
        'deposit_due': 0,
        'cap_note': '',
        'total': 5600,
        'quote_hash': 'q1',
        'expires_at': '2099-01-01T00:00:00Z',
        'rate_version': 'v3',
      });
      expect(c.serverTotalPaise, 5600);
      expect(c.serverWaterPaise, 5600);
      expect(c.serverQuoteHash, 'q1');
      expect(c.codAllowed, isTrue);
      c.dispose();
    });

    test('incomplete quote throws ServerDataException (no local total)', () {
      final c = _c();
      expect(
        () => c.applyQuote({'total': 100}),
        throwsA(isA<ServerDataException>()),
      );
      expect(c.serverTotalPaise, isNull);
      c.dispose();
    });
  });
}
