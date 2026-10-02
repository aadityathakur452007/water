// Vendor demo login: session saved + vendor gate enforced.

import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/features/auth/auth_controller.dart';

class _FakeAuthApi implements AuthApi {
  _FakeAuthApi({required this.role});

  final String role;

  @override
  Future<String> startOtp(String e164) async => 'firebase';

  AuthSession _session() => AuthSession(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
        role: role,
      );

  @override
  Future<AuthSession> verifyOtp(
          {required String idToken, required String deviceId}) async =>
      _session();

  @override
  Future<AuthSession> verifyServerCode(
          {required String phone,
          required String code,
          required String deviceId}) async =>
      _session();

  @override
  Future<AuthSession> demoLogin(
          {required String phone,
          required String code,
          required String deviceId}) async =>
      _session();

  @override
  Future<void> logout(String accessToken) async {}
}

AuthController _controller(String role) => AuthController(
      api: _FakeAuthApi(role: role),
      verifier: _FakeVerifier(),
      store: InMemorySessionStore(),
    );

class _FakeVerifier implements PhoneVerifier {
  @override
  Future<String> requestCode(String e164) async => 'vid';

  @override
  Future<String> confirmCode(
          {required String verificationId,
          required String smsCode}) async =>
      'token';
}

void main() {
  test('demo login with vendor role authenticates', () async {
    final c = _controller('vendor');
    expect(await c.demoLogin('+919000000002', '222222'), isTrue);
    expect(c.isAuthenticated, isTrue);
    expect(c.session?.role, 'vendor');
    c.dispose();
  });

  test('demo login with non-vendor role is rejected', () async {
    final c = _controller('user');
    expect(await c.demoLogin('+919000000001', '111111'), isFalse);
    expect(c.isAuthenticated, isFalse);
    c.dispose();
  });
}
