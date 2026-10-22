import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/features/auth/auth_controller.dart';

void main() {
  group('AuthController OTP', () {
    test('normalizes the phone and returns the server channel', () async {
      final api = _FakeAuthApi();
      final controller = _controller(api);

      final result = await controller.startOtp('98765 43210');

      expect(result?.channel, 'fast2sms');
      expect(result?.serverCode, isTrue);
      expect(api.startedPhone, '+919876543210');
      expect(controller.isAuthenticated, isFalse);
    });

    test('verifies a 6-digit code, persists and authenticates', () async {
      final api = _FakeAuthApi();
      final store = InMemorySessionStore();
      final controller = _controller(api, store: store);

      final ok = await controller.verifyOtp('9876543210', '123456');

      expect(ok, isTrue);
      expect(controller.isAuthenticated, isTrue);
      expect(api.verifiedPhone, '+919876543210');
      expect(api.verifiedCode, '123456');
      expect(await store.readAccessToken(), 'access-token');
      expect(await store.readRole(), 'user');
    });

    test('rejects a malformed code without calling the API', () async {
      final api = _FakeAuthApi();
      final controller = _controller(api);

      final ok = await controller.verifyOtp('9876543210', '12ab');

      expect(ok, isFalse);
      expect(api.verifiedPhone, isNull);
      expect(controller.errorMessage, contains('6-digit'));
    });

    test('surfaces the server rejection and stays signed out', () async {
      final api = _FakeAuthApi()
        ..verifyError = ApiException(
          code: 'OTP_INVALID',
          message: 'That code is incorrect or expired.',
          statusCode: 400,
        );
      final controller = _controller(api);

      final ok = await controller.verifyOtp('9876543210', '000000');

      expect(ok, isFalse);
      expect(controller.isAuthenticated, isFalse);
      expect(controller.errorMessage, 'That code is incorrect or expired.');
    });

    test('rejects a non-customer role and wipes the store', () async {
      final api = _FakeAuthApi()..verifySession = _session(role: 'vendor');
      final store = InMemorySessionStore();
      final controller = _controller(api, store: store);

      final ok = await controller.verifyOtp('9876543210', '123456');

      expect(ok, isFalse);
      expect(controller.isAuthenticated, isFalse);
      expect(await store.readAccessToken(), isNull);
    });

    test('reports a Firebase channel honestly (no fake SMS)', () async {
      final api = _FakeAuthApi()
        ..startResult = const OtpStartResult(
          channel: 'firebase',
          resendAfterSeconds: 30,
        );
      final controller = _controller(api);

      final result = await controller.startOtp('9876543210');

      expect(result?.serverCode, isFalse);
      expect(controller.isAuthenticated, isFalse);
    });
  });
}

AuthController _controller(_FakeAuthApi api, {SessionStore? store}) {
  return AuthController(
    api: api,
    store: store ?? InMemorySessionStore(),
    deviceId: 'test-device',
    restoreTimeout: const Duration(milliseconds: 100),
  );
}

AuthSession _session({String role = 'user'}) => AuthSession(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  expiresAt: DateTime.now().add(const Duration(days: 1)),
  role: role,
);

class _FakeAuthApi implements AuthApi {
  String? startedPhone;
  String? verifiedPhone;
  String? verifiedCode;
  String? verifiedDevice;
  OtpStartResult startResult = const OtpStartResult(
    channel: 'fast2sms',
    resendAfterSeconds: 30,
  );
  AuthSession verifySession = _session();
  Object? startError;
  Object? verifyError;

  @override
  Future<OtpStartResult> startOtp({required String phone}) async {
    startedPhone = phone;
    if (startError != null) throw startError!;
    return startResult;
  }

  @override
  Future<AuthSession> verifyOtp({
    required String phone,
    required String code,
    required String deviceId,
  }) async {
    verifiedPhone = phone;
    verifiedCode = code;
    verifiedDevice = deviceId;
    if (verifyError != null) throw verifyError!;
    return verifySession;
  }

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String deviceId,
  }) async => _session();

  @override
  Future<AuthSession> demoLogin({
    required String phone,
    required String code,
    required String deviceId,
  }) async => _session();

  @override
  Future<void> logout(String accessToken) async {}
}
