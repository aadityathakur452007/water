import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/features/auth/auth_controller.dart';

void main() {
  group('phone normalization', () {
    test('accepts +91, 91, 0 and spaced forms', () {
      for (final raw in [
        '9876543210',
        '+91 98765 43210',
        '919876543210',
        '09876543210',
        '98765-43210',
      ]) {
        expect(normalizeIndianPhone(raw), '9876543210', reason: raw);
      }
    });

    test('rejects landlines, short numbers and 5-series mobiles', () {
      for (final raw in ['', '12345', '5876543210', '91987654321']) {
        expect(normalizeIndianPhone(raw), isNull, reason: raw);
      }
    });
  });

  group('input policy', () {
    test('email is optional and provider-neutral', () {
      expect(isValidUserEmail('you@example.com'), isTrue);
      expect(isValidUserEmail('name+tag@company.co.in'), isTrue);
      expect(isValidUserEmail('not-an-email'), isFalse);
      expect(isValidUserEmail('you@gmail'), isFalse);
    });

    test('password needs 8–128 chars with a letter and a digit', () {
      expect(isValidPassword('water123'), isTrue);
      expect(isValidPassword('allletters'), isFalse);
      expect(isValidPassword('12345678'), isFalse);
      expect(isValidPassword('short1'), isFalse);
    });
  });

  group('register', () {
    test(
      'normalizes the phone, keeps optional email and stores session',
      () async {
        final api = _FakeAuthApi();
        final store = InMemorySessionStore();
        final controller = _controller(api, store: store);

        final ok = await controller.register(
          name: '  Asha  ',
          email: 'ASHA@Example.com',
          rawPhone: '+91 98765 43210',
          password: 'water123',
          confirmPassword: 'water123',
        );

        expect(ok, isTrue);
        expect(api.registerName, 'Asha');
        expect(api.registerEmail, 'asha@example.com');
        expect(api.registerPhone, '+919876543210');
        expect(api.registerPassword, 'water123');
        expect(controller.isAuthenticated, isTrue);
        expect(await store.readAccessToken(), 'access-token');
        expect(await store.readRole(), 'user');
      },
    );

    test('rejects invalid fields without calling the API', () async {
      final api = _FakeAuthApi();
      final controller = _controller(api);

      expect(
        await controller.register(
          name: '',
          rawPhone: '9876543210',
          password: 'water123',
          confirmPassword: 'water123',
        ),
        isFalse,
      );
      expect(controller.errorMessage, contains('name'));

      expect(
        await controller.register(
          name: 'Asha',
          email: 'not-an-email',
          rawPhone: '9876543210',
          password: 'water123',
          confirmPassword: 'water123',
        ),
        isFalse,
      );
      expect(controller.errorMessage, contains('email'));

      expect(
        await controller.register(
          name: 'Asha',
          rawPhone: '5876543210',
          password: 'water123',
          confirmPassword: 'water123',
        ),
        isFalse,
      );
      expect(controller.errorMessage, contains('mobile'));

      expect(
        await controller.register(
          name: 'Asha',
          rawPhone: '9876543210',
          password: 'water123',
          confirmPassword: 'different1',
        ),
        isFalse,
      );
      expect(controller.errorMessage, contains('match'));
      expect(api.registerPhone, isNull);
    });

    test('409 pivots to sign-in without claiming the account', () async {
      final api = _FakeAuthApi()
        ..registerError = ApiException(
          code: 'ACCOUNT_EXISTS',
          message: 'Phone already registered',
          statusCode: 409,
        );
      final controller = _controller(api);

      final ok = await controller.register(
        name: 'Asha',
        rawPhone: '9876543210',
        password: 'water123',
        confirmPassword: 'water123',
      );

      expect(ok, isFalse);
      expect(controller.lastErrorCode, 'ACCOUNT_EXISTS');
      expect(controller.errorMessage, contains('already has an account'));
      expect(controller.isAuthenticated, isFalse);
    });
  });

  group('login', () {
    test('sends normalized phone + password and authenticates', () async {
      final api = _FakeAuthApi();
      final controller = _controller(api);

      final ok = await controller.login(
        rawPhone: '09876543210',
        password: 'water123',
      );

      expect(ok, isTrue);
      expect(api.loginPhone, '+919876543210');
      expect(api.loginPassword, 'water123');
      expect(controller.isAuthenticated, isTrue);
    });

    test('keeps wrong phone and wrong password indistinguishable', () async {
      final api = _FakeAuthApi()
        ..loginError = ApiException(
          code: 'INVALID_CREDENTIALS',
          message: 'Phone or password is incorrect.',
          statusCode: 401,
        );
      final controller = _controller(api);

      final ok = await controller.login(
        rawPhone: '9876543210',
        password: 'wrong123',
      );

      expect(ok, isFalse);
      expect(controller.errorMessage, authStringsHi['invalidCredentials']);
      expect(controller.isAuthenticated, isFalse);
    });

    test('splits offline from 5xx copy', () async {
      final offline = _controller(
        _FakeAuthApi()
          ..loginError = ApiException(
            code: 'NETWORK',
            message: 'Socket error',
            statusCode: 0,
          ),
      );
      await offline.login(rawPhone: '9876543210', password: 'water123');
      expect(offline.errorMessage, authStringsHi['networkError']);

      final server = _controller(
        _FakeAuthApi()
          ..loginError = ApiException(
            code: 'INTERNAL',
            message: 'Internal error',
            statusCode: 503,
          ),
      );
      await server.login(rawPhone: '9876543210', password: 'water123');
      expect(server.errorMessage, authStringsHi['serverError']);
    });

    test('429 exposes the server retry window', () async {
      final controller = _controller(
        _FakeAuthApi()
          ..loginError = ApiException(
            code: 'RATE_LIMITED',
            message: 'Slow down',
            statusCode: 429,
            retryAfterSeconds: 42,
          ),
      );

      await controller.login(rawPhone: '9876543210', password: 'water123');

      expect(controller.errorMessage, authStringsHi['rateLimited']);
      expect(controller.rateLimitSecondsRemaining, inInclusiveRange(1, 42));
    });

    test('rejects a non-customer role and clears the session store', () async {
      final api = _FakeAuthApi()..loginSession = _session(role: 'vendor');
      final store = InMemorySessionStore();
      final controller = _controller(api, store: store);

      final ok = await controller.login(
        rawPhone: '9876543210',
        password: 'water123',
      );

      expect(ok, isFalse);
      expect(controller.isAuthenticated, isFalse);
      expect(await store.readAccessToken(), isNull);
      expect(controller.errorMessage, authStringsHi['notUser']);
    });
  });

  group('session recovery', () {
    test('rotates the stored pair and authenticates', () async {
      final api = _FakeAuthApi()
        ..refreshSession = _session(
          accessToken: 'rotated-access',
          refreshToken: 'rotated-refresh',
        );
      final store = InMemorySessionStore();
      await _saveExpired(store);
      final controller = _controller(api, store: store);

      expect(await controller.recoverSession(), isTrue);

      expect(api.refreshCalls, 1);
      expect(api.refreshTokenSeen, 'old-refresh');
      expect(await store.readAccessToken(), 'rotated-access');
      expect(await store.readRefreshToken(), 'rotated-refresh');
      expect(controller.isAuthenticated, isTrue);
      expect(controller.sessionNotice, isNull);
    });

    test('coalesces concurrent recoveries into one refresh', () async {
      final gate = Completer<void>();
      final api = _FakeAuthApi()
        ..refreshSession = _session(
          accessToken: 'rotated-access',
          refreshToken: 'rotated-refresh',
        )
        ..refreshGate = gate;
      final store = InMemorySessionStore();
      await _saveExpired(store);
      final controller = _controller(api, store: store);

      final first = controller.recoverSession();
      final second = controller.recoverSession();
      await Future<void>.delayed(Duration.zero);
      expect(api.refreshCalls, 1);

      gate.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
    });

    test('failed refresh forces logout with the expiry notice', () async {
      final api = _FakeAuthApi()
        ..refreshError = ApiException(
          code: 'UNAUTH',
          message: 'Session expired.',
          statusCode: 401,
        );
      final store = InMemorySessionStore();
      await _saveExpired(store);
      final controller = _controller(api, store: store);

      expect(await controller.recoverSession(), isFalse);

      expect(controller.isAuthenticated, isFalse);
      expect(controller.status, AuthStatus.idle);
      expect(controller.sessionNotice, authStringsHi['sessionExpired']);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('transient refresh failures keep the stored pair', () async {
      for (final error in [
        ApiException(code: 'NETWORK', message: 'offline', statusCode: 0),
        ApiException(code: 'INTERNAL', message: 'down', statusCode: 503),
        ApiException(
          code: 'RATE_LIMITED',
          message: 'slow down',
          statusCode: 429,
        ),
      ]) {
        final api = _FakeAuthApi()..refreshError = error;
        final store = InMemorySessionStore();
        await _saveExpired(store);
        final controller = _controller(api, store: store);

        expect(await controller.recoverSession(), isFalse);

        expect(controller.isAuthenticated, isFalse);
        expect(controller.sessionNotice, isNull);
        expect(await store.readAccessToken(), 'old-access');
        expect(await store.readRefreshToken(), 'old-refresh');
      }
    });

    test('cold restore keeps the pair when the refresh is transient', () async {
      final api = _FakeAuthApi()
        ..refreshError = ApiException(
          code: 'NETWORK',
          message: 'offline',
          statusCode: 0,
        );
      final store = InMemorySessionStore();
      await _saveExpired(store);
      final controller = _controller(api, store: store);

      expect(await controller.restoreSession(), isTrue);
      expect(controller.isAuthenticated, isFalse);
      expect(controller.sessionNotice, isNull);
      expect(await store.readAccessToken(), 'old-access');
      expect(await store.readRefreshToken(), 'old-refresh');
    });

    test('default restore timeout outlasts the API refresh timeout', () {
      final controller = AuthController(
        api: _FakeAuthApi(),
        store: InMemorySessionStore(),
        deviceId: 'test-device',
      );
      expect(
        controller.restoreTimeout,
        greaterThan(const Duration(seconds: 12)),
      );
    });

    test('cold restore refreshes an expired access token', () async {
      final api = _FakeAuthApi()
        ..refreshSession = _session(
          accessToken: 'restored-access',
          refreshToken: 'restored-refresh',
        );
      final store = InMemorySessionStore();
      await _saveExpired(store);
      final controller = _controller(api, store: store);

      expect(await controller.restoreSession(), isTrue);

      expect(api.refreshCalls, 1);
      expect(controller.isAuthenticated, isTrue);
      expect(await store.readAccessToken(), 'restored-access');
      expect(controller.sessionNotice, isNull);
    });

    test(
      'logout wipes locally, is single-run, and revokes best-effort',
      () async {
        final gate = Completer<void>();
        final api = _FakeAuthApi()..logoutGate = gate;
        final store = InMemorySessionStore();
        final controller = _controller(api, store: store);
        await controller.login(rawPhone: '9876543210', password: 'water123');
        expect(controller.isAuthenticated, isTrue);

        final first = controller.logout();
        final second = controller.logout();
        await Future.wait([first, second]);

        expect(controller.isAuthenticated, isFalse);
        expect(controller.isLoggingOut, isFalse);
        expect(await store.readAccessToken(), isNull);
        expect(api.logoutCalls, 1);

        gate.complete();
        await Future<void>.delayed(Duration.zero);
      },
    );
  });
}

Future<void> _saveExpired(InMemorySessionStore store) => store.saveSession(
  accessToken: 'old-access',
  refreshToken: 'old-refresh',
  expiresAtIso: DateTime.now()
      .subtract(const Duration(minutes: 1))
      .toIso8601String(),
  role: 'user',
);

AuthController _controller(_FakeAuthApi api, {SessionStore? store}) {
  return AuthController(
    api: api,
    store: store ?? InMemorySessionStore(),
    deviceId: 'test-device',
    restoreTimeout: const Duration(milliseconds: 100),
  );
}

AuthSession _session({
  String role = 'user',
  String accessToken = 'access-token',
  String refreshToken = 'refresh-token',
}) => AuthSession(
  accessToken: accessToken,
  refreshToken: refreshToken,
  expiresAt: DateTime.now().add(const Duration(days: 1)),
  role: role,
);

class _FakeAuthApi implements AuthApi {
  String? registerName;
  String? registerEmail;
  String? registerPhone;
  String? registerPassword;
  String? loginPhone;
  String? loginPassword;

  AuthSession registerSession = _session();
  AuthSession loginSession = _session();
  AuthSession refreshSession = _session();
  Object? registerError;
  Object? loginError;
  Object? refreshError;
  int refreshCalls = 0;
  String? refreshTokenSeen;
  Completer<void>? refreshGate;
  int logoutCalls = 0;
  Completer<void>? logoutGate;

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String deviceId,
  }) async {
    registerName = name;
    registerEmail = email;
    registerPhone = phone;
    registerPassword = password;
    if (registerError != null) throw registerError!;
    return registerSession;
  }

  @override
  Future<AuthSession> login({
    required String phone,
    required String password,
    required String deviceId,
  }) async {
    loginPhone = phone;
    loginPassword = password;
    if (loginError != null) throw loginError!;
    return loginSession;
  }

  @override
  Future<void> logout(String accessToken) async {
    logoutCalls += 1;
    final gate = logoutGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<AuthSession> refresh({required String refreshToken}) async {
    refreshCalls += 1;
    refreshTokenSeen = refreshToken;
    final gate = refreshGate;
    if (gate != null) await gate.future;
    if (refreshError != null) throw refreshError!;
    return refreshSession;
  }
}
