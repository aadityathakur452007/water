// Vendor auth validation: phone normalize + mask + access-code rules.

import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/features/auth/auth_controller.dart';

void main() {
  group('normalizeIndianPhone', () {
    test('accepts plain 10-digit', () {
      expect(normalizeIndianPhone('9302190067'), '9302190067');
    });
    test('strips +91, spaces, leading 0', () {
      expect(normalizeIndianPhone('+91 93021 90067'), '9302190067');
      expect(normalizeIndianPhone('919302190067'), '9302190067');
      expect(normalizeIndianPhone('09302190067'), '9302190067');
    });
    test('rejects bad numbers', () {
      expect(normalizeIndianPhone('12345'), isNull);
      expect(normalizeIndianPhone('5302190067'), isNull); // 5-led
      expect(normalizeIndianPhone(''), isNull);
    });
  });

  test('maskPhone hides first digits', () {
    expect(maskPhone('9302190067'), '+91 ••••• 90067');
  });

  test('isValidIndianPhone mirrors normalize', () {
    expect(isValidIndianPhone('9302190067'), isTrue);
    expect(isValidIndianPhone('123'), isFalse);
  });

  group('isValidAccessCode (code-screen validation)', () {
    test('accepts 4+ chars, trimmed', () {
      expect(isValidAccessCode('abcd'), isTrue);
      expect(isValidAccessCode('  abcdef123  '), isTrue);
    });
    test('rejects blank and short codes', () {
      expect(isValidAccessCode(''), isFalse);
      expect(isValidAccessCode('   '), isFalse);
      expect(isValidAccessCode('abc'), isFalse);
    });
  });
}
