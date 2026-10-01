// F2 — Auth validation unit tests (normalize / regex / edge cases +
// controller attempt-cooldown-logout behavior). Run: flutter test test/auth_validation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_app/features/auth/auth_controller.dart';

class _FakeApi implements AuthApi {
  AuthSession? sessionToReturn;
  bool failStart = false;
  String channelToReturn = 'firebase';
  Map<String, String>? serverCodeArgs;

  @override
  Future<String> startOtp(String e164) async {
    if (failStart) throw Exception('offline');
    return channelToReturn;
  }

  @override
  Future<AuthSession> verifyOtp({
    required String idToken,
    required String deviceId,
  }) async {
    final s = sessionToReturn;
    if (s == null) throw Exception('no session');
    return s;
  }

  @override
  Future<AuthSession> verifyServerCode({
    required String phone,
    required String code,
    required String deviceId,
  }) async {
    serverCodeArgs = {'phone': phone, 'code': code, 'deviceId': deviceId};
    final s = sessionToReturn;
    if (s == null) throw Exception('no session');
    return s;
  }

  @override
  Future<void> logout(String accessToken) async {}
}

class _FakeVerifier implements PhoneVerifier {
  static const goodCode = '123456';

  @override
  Future<String> requestCode(String e164) async => 'vid-$e164';

  @override
  Future<String> confirmCode({
    required String verificationId,
    required String smsCode,
  }) async {
    if (smsCode == goodCode) return 'id-token';
    throw Exception('invalid code');
  }
}

/// Counts Firebase requestCode calls (proves the sms channel skips Firebase).
class _CountingVerifier implements PhoneVerifier {
  _CountingVerifier(this.onRequest);
  final void Function() onRequest;
  final _FakeVerifier _inner = _FakeVerifier();

  @override
  Future<String> requestCode(String e164) {
    onRequest();
    return _inner.requestCode(e164);
  }

  @override
  Future<String> confirmCode({
    required String verificationId,
    required String smsCode,
  }) =>
      _inner.confirmCode(verificationId: verificationId, smsCode: smsCode);
}

AuthController _controller({
  _FakeApi? api,
  int cooldown = 60,
}) {
  return AuthController(
    api: api ?? _FakeApi(),
    verifier: _FakeVerifier(),
    store: InMemorySessionStore(),
    deviceId: 'test-device',
    resendCooldown: cooldown,
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

  group('maskPhone', () {
    test('hides all but last 5', () {
      expect(maskPhone('9876543210'), '+91 ••••• 43210');
    });
  });

  group('AuthController', () {
    test('sendOtp → codeSent + 60s cooldown', () async {
      final c = _controller(cooldown: 60);
      await c.sendOtp('98765 43210');
      expect(c.status, AuthStatus.codeSent);
      expect(c.digits10, '9876543210');
      expect(c.resendInSeconds, 60);
      expect(c.canResend, isFalse);
      c.dispose();
    });

    test('sendOtp with bad number fails without cooldown', () async {
      final c = _controller();
      await c.sendOtp('12345');
      expect(c.status, AuthStatus.idle);
      expect(c.errorMessage, authStringsHi['phoneError']);
      c.dispose();
    });

    test('5 wrong codes → mustResend (forced resend)', () async {
      final c = _controller();
      await c.sendOtp('9876543210');
      for (var i = 0; i < 5; i++) {
        await c.confirm('000000');
      }
      expect(c.attempts, 5);
      expect(c.mustResend, isTrue);
      expect(c.errorMessage, authStringsHi['tooManyAttempts']);
      // Further confirms are blocked until resend:
      await c.confirm('123456');
      expect(c.mustResend, isTrue);
      c.dispose();
    });

    test('resend resets attempts after cooldown', () async {
      final c = _controller(cooldown: 60);
      await c.sendOtp('9876543210');
      await c.confirm('000000');
      expect(c.attempts, 1);
      c.debugExpireCooldown();
      expect(c.canResend, isTrue);
      await c.resend();
      expect(c.attempts, 0);
      expect(c.mustResend, isFalse);
      expect(c.status, AuthStatus.codeSent);
      c.dispose();
    });

    test('sms channel skips Firebase and posts the typed code', () async {
      final api = _FakeApi()
        ..channelToReturn = 'sms'
        ..sessionToReturn = AuthSession(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(minutes: 30)),
          role: 'user',
        );
      var firebaseCalls = 0;
      final verifier = _CountingVerifier(() => firebaseCalls++);
      final c = AuthController(
        api: api,
        verifier: verifier,
        store: InMemorySessionStore(),
        deviceId: 'test-device',
      );
      await c.sendOtp('9876543210');
      expect(c.status, AuthStatus.codeSent);
      expect(firebaseCalls, 0); // no Firebase request on the sms channel
      await c.confirm('654321');
      expect(c.status, AuthStatus.authenticated);
      expect(api.serverCodeArgs, {
        'phone': '+919876543210',
        'code': '654321',
        'deviceId': 'test-device',
      });
      c.dispose();
    });

    test('good code → authenticated + session persisted', () async {
      final api = _FakeApi()
        ..sessionToReturn = AuthSession(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(minutes: 30)),
          role: 'user',
        );
      final c = _controller(api: api);
      await c.sendOtp('9876543210');
      await c.confirm('123456');
      expect(c.status, AuthStatus.authenticated);
      expect(c.isAuthenticated, isTrue);
      c.dispose();
    });

    test('expired code path surfaces expired message', () async {
      final c = _controller();
      await c.sendOtp('9876543210');
      c.expireCode();
      expect(c.codeExpired, isTrue);
      await c.confirm('123456');
      expect(c.errorMessage, authStringsHi['codeExpired']);
      c.dispose();
    });

    test('logout clears session and store', () async {
      final api = _FakeApi()
        ..sessionToReturn = AuthSession(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(minutes: 30)),
          role: 'user',
        );
      final store = InMemorySessionStore();
      final c = AuthController(
        api: api,
        verifier: _FakeVerifier(),
        store: store,
      );
      await c.sendOtp('9876543210');
      await c.confirm('123456');
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
        verifier: _FakeVerifier(),
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
        verifier: _FakeVerifier(),
        store: store,
      );
      await c2.restoreSession();
      expect(c2.isAuthenticated, isFalse);
      c.dispose();
      c2.dispose();
    });
  });
}
