// User demo login: session saved + user role gate enforced.

import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_app/features/auth/auth_controller.dart';

class _FakeAuthApi implements AuthApi {
  _FakeAuthApi({required this.role});

  final String role;

  AuthSession _session() => AuthSession(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        role: role,
      );

  @override
  Future<AuthSession> register(
          {required String name,
          required String phone,
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
      store: InMemorySessionStore(),
    );

void main() {
  test('demo login with user role authenticates', () async {
    final c = _controller('user');
    expect(await c.demoLogin('+919000000001', '111111'), isTrue);
    expect(c.isAuthenticated, isTrue);
    c.dispose();
  });

  test('demo login with vendor role is rejected in the customer app',
      () async {
    final c = _controller('vendor');
    expect(await c.demoLogin('+919000000002', '222222'), isFalse);
    expect(c.isAuthenticated, isFalse);
    c.dispose();
  });
}
