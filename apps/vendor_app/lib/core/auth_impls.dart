// Auth seams — access-code-only (028, spec §4). No phone-OTP SDK anywhere:
// vendor login is phone + admin-issued code → POST /v1/auth/vendor/login.
// Demo door (server-gated) stays as the QA fallback.

import '../features/auth/auth_controller.dart';
import 'api_client.dart';

class ApiBackedAuthApi implements AuthApi {
  ApiBackedAuthApi(this._api);

  final ApiClient _api;

  AuthSession _toSession(Map<String, dynamic> raw) {
    final expiresAt = DateTime.tryParse((raw['expires_at'] ?? '') as String) ??
        DateTime.now().add(const Duration(minutes: 30));
    return AuthSession(
      accessToken: (raw['access_token'] ?? '') as String,
      refreshToken: (raw['refresh_token'] ?? '') as String,
      expiresAt: expiresAt,
      role: (raw['role'] ?? 'vendor') as String,
      newDeviceAlert: (raw['new_device_alert'] ?? false) as bool,
    );
  }

  @override
  Future<AuthSession> vendorCodeLogin({
    required String phone,
    required String code,
    required String deviceId,
  }) async {
    final raw = await _api.send(
      'POST',
      '/auth/vendor/login',
      body: {
        'phone': phone,
        'code': code,
        'device': {'id': deviceId},
      },
      authed: false,
    );
    if (raw is! Map<String, dynamic>) {
      throw ApiException(
        code: 'UNKNOWN',
        message: 'Malformed login response',
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
  Future<AuthSession> refreshSession({
    required String refreshToken,
    required String deviceId,
  }) async {
    final raw = await _api.send(
      'POST',
      '/auth/refresh',
      body: {
        'refresh_token': refreshToken,
        'device': {'id': deviceId},
      },
      authed: false,
      // The rotation itself must never trigger the 401→refresh hook
      // (that would recurse); failures surface to the caller directly.
      attemptRefresh: false,
    );
    if (raw is! Map<String, dynamic>) {
      throw ApiException(
        code: 'UNKNOWN',
        message: 'Malformed refresh response',
        statusCode: 0,
      );
    }
    return _toSession(raw);
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
