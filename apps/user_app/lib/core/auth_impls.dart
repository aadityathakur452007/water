// F5 — Real seam implementations for F2's auth abstractions.
//
// [ApiBackedAuthApi] speaks the Workers contract §4.1 exactly (otp/start →
// 202, otp/verify {firebase_id_token, device} → session, logout). Bearer +
// X-Device-Id ride on [ApiClient].
//
// [StubPhoneVerifier] is the v1 dev verifier: it accepts the code `123456`
// and mints a placeholder id-token so the full flow runs end-to-end against
// a mocking/staging backend. TODO(F1): swap for a FirebaseAuth-backed
// PhoneVerifier (verifyPhoneNumber callbacks) once google-services.json
// lands — the seam contract is already identical to Firebase's callbacks.

import 'package:flutter/foundation.dart';

import '../features/auth/auth_controller.dart';
import 'api_client.dart';

/// Contract §4.1 over [ApiClient].
class ApiBackedAuthApi implements AuthApi {
  ApiBackedAuthApi(this._api);

  final ApiClient _api;

  @override
  Future<void> startOtp(String e164) async {
    await _api.send(
      'POST',
      '/auth/otp/start',
      body: {'phone': e164},
      authed: false,
    );
  }

  @override
  Future<AuthSession> verifyOtp({
    required String idToken,
    required String deviceId,
  }) async {
    final raw = await _api.send(
      'POST',
      '/auth/otp/verify',
      body: {
        'firebase_id_token': idToken,
        'device': deviceId,
      },
      authed: false,
    );
    if (raw is! Map<String, dynamic>) {
      throw ApiException(
        code: 'UNKNOWN',
        message: 'Malformed verify response',
        statusCode: 0,
      );
    }
    final expiresAt = DateTime.tryParse((raw['expires_at'] ?? '') as String) ??
        DateTime.now().add(const Duration(minutes: 30));
    return AuthSession(
      accessToken: (raw['access_token'] ?? '') as String,
      refreshToken: (raw['refresh_token'] ?? '') as String,
      expiresAt: expiresAt,
      role: (raw['role'] ?? 'user') as String,
      newDeviceAlert: (raw['new_device_alert'] ?? false) as bool,
    );
  }

  @override
  Future<void> logout(String accessToken) async {
    await _api.send('POST', '/auth/logout', body: null, authed: true);
  }
}

/// Dev verifier (see header). Real Firebase swap is F1-owned.
class StubPhoneVerifier implements PhoneVerifier {
  @override
  Future<String> requestCode(String e164) async {
    debugPrint('[StubPhoneVerifier] OTP requested for $e164 (dev: use 123456)');
    return 'stub-vid';
  }

  @override
  Future<String> confirmCode({
    required String verificationId,
    required String smsCode,
  }) async {
    if (smsCode == '123456') return 'stub-id-token';
    throw Exception('invalid code (dev verifier expects 123456)');
  }
}
