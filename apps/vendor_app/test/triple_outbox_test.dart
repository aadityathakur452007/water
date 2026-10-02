// Triple payload + money display rules (pure logic, no plugins).

import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/core/money.dart';
import 'package:vendor_app/features/stops/stops_controller.dart';

void main() {
  group('rupees', () {
    test('formats paise to Rs', () {
      expect(rupees(8600), 'Rs 86');
      expect(rupees(15000), 'Rs 150');
      expect(rupees(8650), 'Rs 86.50');
      expect(rupees(0), 'Rs 0');
    });
  });

  test('depositDueRs = max(0, N-E) x 150', () {
    expect(depositDueRs(2, 1), 150);
    expect(depositDueRs(2, 2), 0);
    expect(depositDueRs(1, 3), 0);
  });

  test('capChargeRs = M x 3', () {
    expect(capChargeRs(2), 6);
    expect(capChargeRs(0), 0);
  });

  group('buildTripleBody', () {
    test('builds version-fenced body in paise', () {
      final b = buildTripleBody(
        fullsGiven: 2,
        emptiesBack: 1,
        cashPaise: 8600,
        upiPaise: 0,
        capsMissing: 1,
        version: 3,
      );
      expect(b['fulls_given'], 2);
      expect(b['version'], 3);
      expect(b['cash'], 8600);
      expect(b['seal_ok'], isTrue);
    });

    test('rejects tendered-change != cash', () {
      expect(
        () => buildTripleBody(
          fullsGiven: 1,
          emptiesBack: 1,
          cashPaise: 8600,
          upiPaise: 0,
          capsMissing: 0,
          tenderedPaise: 10000,
          changePaise: 1000, // 9000 != 8600
          version: 1,
        ),
        throwsArgumentError,
      );
    });

    test('accepts matching tendered/change', () {
      final b = buildTripleBody(
        fullsGiven: 1,
        emptiesBack: 1,
        cashPaise: 8600,
        upiPaise: 0,
        capsMissing: 0,
        tenderedPaise: 10000,
        changePaise: 1400,
        version: 1,
      );
      expect(b['tendered'], 10000);
    });
  });

  test('idempotency keys are unique per commit', () {
    expect(newIdempotencyKey(), isNot(newIdempotencyKey()));
  });
}
