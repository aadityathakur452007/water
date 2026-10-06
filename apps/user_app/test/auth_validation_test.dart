// User name+number register validation (028): normalize / mask / name rules
// + controller register/demo/logout behavior. Run:
// flutter test test/auth_validation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/features/auth/auth_controller.dart';

class _FakeApi implements AuthApi {
  _FakeApi({this.role = 'user', this.throwStatus, this.throwMessage = 'err'});

  final String role;
  final int? throwStatus;
  final String throwMessage;
  int registerCalls = 0;
  Map<String, String>? lastRegisterArgs;

  AuthSession _session() => AuthSession(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        role: role,
        verified: false,
      );

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String deviceId,
  }) async {
    registerCalls += 1;
    lastRegisterArgs = {
      'name': name,
      'email': email,
      'phone': phone,
      'deviceId': deviceId,
    };
    final status = throwStatus;
    if (status != null) {
      throw ApiException(
        code: 'ERR',
        message: throwMessage,
        statusCode: status,
      );
    }
    return _session();
  }

  @override
  Future<void> logout(String accessToken) async {}

  @override
  Future<AuthSession> demoLogin({
    required String phone,
    required String code,
    required String deviceId,
  }) async {
    return _session();
  }
}

AuthController _controller({_FakeApi? api}) {
  return AuthController(
    api: api ?? _FakeApi(),
    store: InMemorySessionStore(),
    deviceId: 'test-device',
  );
}

void main() {
  group('normalizeIndianPhone', () {
    test('plain 10-digit starting 6-9 is valid', () {
      expect(normalizeIndianPhone('9876543210'), '9876543210');
      expect(normalizeIndianPhone('6123456789'), '6123456789');
      expect(normalizeIndianPhone('8123456789'), '8123456789');
      expect(normalizeIndianPhone('7123456789'), '7123456789');
    });

    test('91 / +91 / 0 variants normalize', () {
      expect(normalizeIndianPhone('+919876543210'), '9876543210');
      expect(normalizeIndianPhone('919876543210'), '9876543210');
      expect(normalizeIndianPhone('09876543210'), '9876543210');
      expect(normalizeIndianPhone('+91 98765 43210'), '9876543210');
      expect(normalizeIndianPhone('91-98765-43210'), '9876543210');
      expect(normalizeIndianPhone('  98 765 43210  '), '9876543210');
    });

    test('10-digit 91-series stays intact (no over-strip)', () {
      expect(normalizeIndianPhone('9100000000'), '9100000000');
    });

    test('invalid series start digits rejected', () {
      for (final bad in ['1234567890', '2876543210', '5876543210']) {
        expect(isValidIndianPhone(bad), isFalse, reason: bad);
      }
      // Leading-0 + 8-series: strips 0 → 9 digits → invalid.
      expect(normalizeIndianPhone('0876543210'), isNull);
    });

    test('wrong lengths rejected', () {
      expect(normalizeIndianPhone('987654321'), isNull); // 9 digits
      expect(normalizeIndianPhone('98765432101'), isNull); // 11, no leading 0
      expect(normalizeIndianPhone('91987654321'), isNull); // 11 starting 91
      expect(normalizeIndianPhone(''), isNull);
      expect(normalizeIndianPhone('abcd'), isNull);
      expect(normalizeIndianPhone('+1 4155552671'), isNull); // non-IN
    });
  });

  group('isValidUserName', () {
    test('accepts 1–100 trimmed chars', () {
      expect(isValidUserName('Naya User'), isTrue);
      expect(isValidUserName('  A  '), isTrue);
      expect(isValidUserName('a' * 100), isTrue);
    });

    test('rejects blank and >100 chars', () {
      expect(isValidUserName(''), isFalse);
      expect(isValidUserName('   '), isFalse);
      expect(isValidUserName('a' * 101), isFalse);
    });
  });

  group('maskPhone', () {
    test('hides all but last 5', () {
      expect(maskPhone('9876543210'), '+91 ••••• 43210');
    });
  });

  group('isValidUserEmail', () {
    test('accepts normal addresses', () {
      expect(isValidUserEmail('aap@example.com'), isTrue);
      expect(isValidUserEmail('  AAP@Example.IN  '), isTrue);
      expect(isValidUserEmail('a.b+tag@sub.domain.co'), isTrue);
    });

    test('rejects blank and malformed', () {
      for (final bad in [
        '',
        '   ',
        'nope',
        'a@b',
        'a@b.',
        '@x.in',
        'a b@c.in',
        'a' * 250 + '@x.in', // over 254 chars
      ]) {
        expect(isValidUserEmail(bad), isFalse, reason: bad);
      }
    });
  });

  group('AuthController.registerNameNumber', () {
    test('valid name+email+number → authenticated + session persisted',
        () async {
      final api = _FakeApi();
      final c = _controller(api: api);
      expect(
        await c.registerNameNumber(
          'Naya User',
          'naya@example.in',
          '98765 43210',
        ),
        isTrue,
      );
      expect(c.status, AuthStatus.authenticated);
      expect(c.isAuthenticated, isTrue);
      expect(c.session?.role, 'user');
      expect(c.session?.verified, isFalse);
      expect(api.lastRegisterArgs, {
        'name': 'Naya User',
        'email': 'naya@example.in',
        'phone': '+919876543210',
        'deviceId': 'test-device',
      });
      c.dispose();
    });

    test('bad phone fails without calling api', () async {
      final api = _FakeApi();
      final c = _controller(api: api);
      expect(
        await c.registerNameNumber('Naya User', 'naya@example.in', '12345'),
        isFalse,
      );
      expect(api.registerCalls, 0);
      expect(c.errorMessage, authStringsHi['phoneError']);
      expect(c.status, AuthStatus.idle);
      c.dispose();
    });

    test('blank name fails without calling api', () async {
      final api = _FakeApi();
      final c = _controller(api: api);
      expect(
        await c.registerNameNumber('   ', 'naya@example.in', '9876543210'),
        isFalse,
      );
      expect(api.registerCalls, 0);
      expect(c.errorMessage, authStringsHi['nameError']);
      expect(c.status, AuthStatus.idle);
      c.dispose();
    });

    test('bad email fails without calling api', () async {
      final api = _FakeApi();
      final c = _controller(api: api);
      expect(
        await c.registerNameNumber('Naya User', 'not-an-email', '9876543210'),
        isFalse,
      );
      expect(api.registerCalls, 0);
      expect(c.errorMessage, authStringsHi['emailError']);
      expect(c.status, AuthStatus.idle);
      c.dispose();
    });

    test('non-user role is rejected + wiped', () async {
      final c = _controller(api: _FakeApi(role: 'vendor'));
      expect(
        await c.registerNameNumber(
          'Naya User',
          'naya@example.in',
          '9876543210',
        ),
        isFalse,
      );
      expect(c.isAuthenticated, isFalse);
      expect(c.errorMessage, authStringsHi['notUser']);
      c.dispose();
    });

    test('422 maps to staff-number copy', () async {
      final c = _controller(
        api: _FakeApi(throwStatus: 422, throwMessage: 'ROLE_RESERVED'),
      );
      expect(
        await c.registerNameNumber(
          'Intruder',
          'intruder@example.in',
          '9876543210',
        ),
        isFalse,
      );
      expect(c.isAuthenticated, isFalse);
      expect(c.errorMessage, authStringsHi['staffNumber']);
      c.dispose();
    });

    test('429 maps to rate-limit copy', () async {
      final c = _controller(api: _FakeApi(throwStatus: 429));
      expect(
        await c.registerNameNumber(
          'Naya User',
          'naya@example.in',
          '9876543210',
        ),
        isFalse,
      );
      expect(c.errorMessage, authStringsHi['rateLimited']);
      c.dispose();
    });

    test('400 surfaces the server message', () async {
      final c = _controller(
        api: _FakeApi(throwStatus: 400, throwMessage: 'Bad phone'),
      );
      expect(
        await c.registerNameNumber(
          'Naya User',
          'naya@example.in',
          '9876543210',
        ),
        isFalse,
      );
      expect(c.errorMessage, 'Bad phone');
      c.dispose();
    });

    test('logout clears session and store', () async {
      final store = InMemorySessionStore();
      final c = AuthController(
        api: _FakeApi(),
        store: store,
        deviceId: 'test-device',
      );
      await c.registerNameNumber(
        'Naya User',
        'naya@example.in',
        '9876543210',
      );
      expect(c.isAuthenticated, isTrue);
      await c.logout();
      expect(c.isAuthenticated, isFalse);
      expect(c.status, AuthStatus.idle);
      expect(await store.readAccessToken(), isNull);
      c.dispose();
    });

    test('restoreSession revives valid, drops expired', () async {
      final store = InMemorySessionStore();
      await store.saveSession(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAtIso:
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
        role: 'user',
      );
      final c = AuthController(
        api: _FakeApi(),
        store: store,
      );
      await c.restoreSession();
      expect(c.isAuthenticated, isTrue);

      await store.saveSession(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAtIso:
            DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
        role: 'user',
      );
      final c2 = AuthController(
        api: _FakeApi(),
        store: store,
      );
      await c2.restoreSession();
      expect(c2.isAuthenticated, isFalse);
      c.dispose();
      c2.dispose();
    });
  });
}
