// F5 — Real seam implementations for F2's auth abstractions.
//
// [ApiBackedAuthApi] speaks the Workers contract §4.1 exactly (otp/start →
// 202, otp/verify {firebase_id_token, device} → session, logout). Bearer +
// X-Device-Id ride on [ApiClient].
//
// [FirebasePhoneVerifier] is the production verifier (real Firebase SMS via
// google-services.json). [StubPhoneVerifier] exists ONLY for widget tests —
// it is never wired in main.dart, so no demo login path ships to users.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
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

/// Dev verifier (see header). Kept for widget tests; production uses
/// [FirebasePhoneVerifier] (wired in main.dart).
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

/// Production verifier: real Firebase SMS via google-services.json.
///
/// Seam contract is unchanged (verificationId in/out, idToken out), so
/// callers are untouched. Auto-retrieval (Android) short-circuits confirm
/// through the `_auto` sentinel; manual entry uses PhoneAuthCredential.
class FirebasePhoneVerifier implements PhoneVerifier {
  String? _autoToken;

  @override
  Future<String> requestCode(String e164) {
    final done = Completer<String>();
    FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: e164,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          final userCredential =
              await FirebaseAuth.instance.signInWithCredential(credential);
          _autoToken = await userCredential.user?.getIdToken();
          if (!done.isCompleted) done.complete('_auto');
        } catch (e) {
          if (!done.isCompleted) done.completeError(e);
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!done.isCompleted) {
          done.completeError(Exception(e.message ?? 'phone verification failed'));
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!done.isCompleted) done.complete(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        if (!done.isCompleted) done.complete(verificationId);
      },
    );
    return done.future;
  }

  @override
  Future<String> confirmCode({
    required String verificationId,
    required String smsCode,
  }) async {
    if (verificationId == '_auto' && _autoToken != null) return _autoToken!;
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);
    final token = await userCredential.user?.getIdToken();
    if (token == null || token.isEmpty) throw Exception('sign-in failed');
    return token;
  }
}
