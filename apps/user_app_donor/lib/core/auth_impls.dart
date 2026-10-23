// User auth seams over the Workers API (034). Password register/login plus the
// server-gated demo door. Legacy phone-code sign-in was retired server-side (410) and has no
// client method here by design.

import '../features/auth/auth_controller.dart';
import 'api_client.dart';

/// Contract §4.1/§6.5 over [ApiClient].
class ApiBackedAuthApi implements AuthApi {
  ApiBackedAuthApi(this._api);

  final ApiClient _api;

  AuthSession _toSession(Map<String, dynamic> raw) {
    // Absolute 30-day cap backstop: the server always sends expires_at, but
    // a missing/invalid field must never strand the user as instantly-expired.
    final expiresAt =
        DateTime.tryParse((raw['expires_at'] ?? '').toString()) ??
        DateTime.now().add(const Duration(days: 30));
    return AuthSession(
      accessToken: (raw['access_token'] ?? '').toString(),
      refreshToken: (raw['refresh_token'] ?? '').toString(),
      expiresAt: expiresAt,
      role: (raw['role'] ?? 'user').toString(),
      newDeviceAlert: raw['new_device_alert'] == true,
      verified: raw['verified'] == true,
    );
  }

  Map<String, dynamic> _requireMap(dynamic raw, String label) {
    if (raw is Map<String, dynamic>) return raw;
    throw ApiException(
      code: 'UNKNOWN',
      message: 'Malformed $label response',
      statusCode: 0,
    );
  }

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String deviceId,
  }) async {
    final raw = await _api.send(
      'POST',
      '/auth/user/register',
      body: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'device': {'id': deviceId},
      },
      authed: false,
    );
    return _toSession(_requireMap(raw, 'register'));
  }

  @override
  Future<AuthSession> login({
    required String phone,
    required String password,
    required String deviceId,
  }) async {
    final raw = await _api.send(
      'POST',
      '/auth/user/login',
      body: {
        'phone': phone,
        'password': password,
        'device': {'id': deviceId},
      },
      authed: false,
    );
    return _toSession(_requireMap(raw, 'login'));
  }

  @override
  Future<void> logout(String accessToken) async {
    await _api.send('POST', '/auth/logout', body: null, authed: true);
  }

  @override
  Future<AuthSession> demoLogin({
    required String phone,
    required String code,
    required String deviceId,
  }) async {
    final raw = await _api.send(
      'POST',
      '/auth/demo',
      body: {
        'phone': phone,
        'demo_code': code,
        'device': {'id': deviceId},
      },
      authed: false,
    );
    return _toSession(_requireMap(raw, 'demo'));
  }
}
