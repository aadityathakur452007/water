// Vendor access-code + demo login: session saved + vendor gate enforced +
// generic-401 mapping. No verifier/channel cases (OTP deleted, 028 §4).

import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/features/auth/auth_controller.dart';
import 'package:vendor_app/features/auth/vendor_strings.dart';

class _FakeAuthApi implements AuthApi {
  _FakeAuthApi({required this.role, this.throwStatus});

  final String role;
  final int? throwStatus;
  int vendorCalls = 0;

  AuthSession _session() => AuthSession(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
        role: role,
      );

  @override
  Future<AuthSession> vendorCodeLogin({
    required String phone,
    required String code,
    required String deviceId,
  }) async {
    vendorCalls += 1;
    final status = throwStatus;
    if (status != null) {
      throw ApiException(code: 'ERR', message: 'err', statusCode: status);
    }
    return _session();
  }

  @override
  Future<AuthSession> demoLogin({
    required String phone,
    required String code,
    required String deviceId,
  }) async =>
      _session();

  @override
  Future<void> logout(String accessToken) async {}

  @override
  Future<AuthSession> refreshSession({
    required String refreshToken,
    required String deviceId,
  }) async =>
      _session();
}

AuthController _controller(String role, {int? throwStatus}) => AuthController(
      api: _FakeAuthApi(role: role, throwStatus: throwStatus),
      store: InMemorySessionStore(),
    );

void main() {
  test('code login with vendor role authenticates', () async {
    final c = _controller('vendor');
    expect(await c.codeLogin('9302190067', 'admin-code-1'), isTrue);
    expect(c.isAuthenticated, isTrue);
    expect(c.session?.role, 'vendor');
    c.dispose();
  });

  test('code login with non-vendor role is rejected + wiped', () async {
    final c = _controller('user');
    expect(await c.codeLogin('9302190067', 'admin-code-1'), isFalse);
    expect(c.isAuthenticated, isFalse);
    expect(c.errorMessage, vendorStringsHi['notVendor']);
    c.dispose();
  });

  test('code login maps 401 to generic copy', () async {
    final c = _controller('vendor', throwStatus: 401);
    expect(await c.codeLogin('9302190067', 'wrong-code'), isFalse);
    expect(c.isAuthenticated, isFalse);
    expect(c.errorMessage, vendorStringsHi['invalidCredentials']);
    c.dispose();
  });

  test('code login maps 429 to rate-limit copy', () async {
    final c = _controller('vendor', throwStatus: 429);
    expect(await c.codeLogin('9302190067', 'admin-code-1'), isFalse);
    expect(c.errorMessage, vendorStringsHi['rateLimited']);
    c.dispose();
  });

  test('code login rejects bad phone without calling api', () async {
    final api = _FakeAuthApi(role: 'vendor');
    final c = AuthController(api: api, store: InMemorySessionStore());
    expect(await c.codeLogin('123', 'admin-code-1'), isFalse);
    expect(api.vendorCalls, 0);
    expect(c.errorMessage, vendorStringsHi['phoneError']);
    c.dispose();
  });

  test('code login rejects short code without calling api', () async {
    final api = _FakeAuthApi(role: 'vendor');
    final c = AuthController(api: api, store: InMemorySessionStore());
    expect(await c.codeLogin('9302190067', 'abc'), isFalse);
    expect(api.vendorCalls, 0);
    expect(c.errorMessage, vendorStringsHi['codeError']);
    c.dispose();
  });

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
