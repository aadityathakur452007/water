// User auth seams — name+email+phone register. No OTP SDK anywhere:
// name + email + number → POST /v1/auth/user/register. Demo door
// (server-gated) stays as the QA fallback.

import '../features/auth/auth_controller.dart';
import 'api_client.dart';

/// Contract §4.1 (028) over [ApiClient].
class ApiBackedAuthApi implements AuthApi {
  ApiBackedAuthApi(this._api);

  final ApiClient _api;

  AuthSession _toSession(Map<String, dynamic> raw) {
    // Absolute 30-day cap backstop: the server always sends expires_at, but
    // a missing field must never strand the user as instantly-expired.
    final expiresAt = DateTime.tryParse((raw['expires_at'] ?? '') as String) ??
        DateTime.now().add(const Duration(days: 30));
    return AuthSession(
      accessToken: (raw['access_token'] ?? '') as String,
      refreshToken: (raw['refresh_token'] ?? '') as String,
      expiresAt: expiresAt,
      role: (raw['role'] ?? 'user') as String,
      newDeviceAlert: (raw['new_device_alert'] ?? false) as bool,
      verified: (raw['verified'] ?? false) as bool,
    );
  }

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String deviceId,
  }) async {
    final raw = await _api.send(
      'POST',
      '/auth/user/register',
      body: {
        'name': name,
        'email': email,
        'phone': phone,
        'device': {'id': deviceId},
      },
      authed: false,
    );
    if (raw is! Map<String, dynamic>) {
      throw ApiException(
        code: 'UNKNOWN',
        message: 'Malformed register response',
        statusCode: 0,
      );
    }
    return _toSession(raw);
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
    if (raw is! Map<String, dynamic>) {
      throw ApiException(
        code: 'UNKNOWN',
        message: 'Malformed demo response',
        statusCode: 0,
      );
    }
    return _toSession(raw);
  }
}
