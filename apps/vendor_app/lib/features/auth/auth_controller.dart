// Vendor auth state — mirrors user_app AuthController (same seams, same
// cooldown/attempt/expiry logic). Differences: vendor Hindi strings,
// role gate (role must be `vendor`, else rejected with notVendor), no guest.

// ignore_for_file: prefer_initializing_formals
// (Ctor param `api` must stay public-named for main.dart wiring.)

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'vendor_strings.dart';

String? normalizeIndianPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('91') && digits.length == 12) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0') && digits.length == 11) {
    digits = digits.substring(1);
  }
  if (RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) return digits;
  return null;
}

bool isValidIndianPhone(String raw) => normalizeIndianPhone(raw) != null;

String maskPhone(String digits10) =>
    '+91 ••••• ${digits10.substring(digits10.length - 5)}';

@immutable
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.role,
    this.newDeviceAlert = false,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String role;
  final bool newDeviceAlert;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

abstract class SessionStore {
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String expiresAtIso,
    required String role,
  });
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<String?> readExpiryIso();
  Future<String?> readRole();
  Future<void> clear();
}

class InMemorySessionStore implements SessionStore {
  String? _access;
  String? _refresh;
  String? _expiryIso;
  String? _role;

  @override
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String expiresAtIso,
    required String role,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
    _expiryIso = expiresAtIso;
    _role = role;
  }

  @override
  Future<String?> readAccessToken() async => _access;

  @override
  Future<String?> readRefreshToken() async => _refresh;

  @override
  Future<String?> readExpiryIso() async => _expiryIso;

  @override
  Future<String?> readRole() async => _role;

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _expiryIso = null;
    _role = null;
  }
}

abstract class AuthApi {
  Future<String> startOtp(String e164);
  Future<AuthSession> verifyOtp({
    required String idToken,
    required String deviceId,
  });
  Future<AuthSession> verifyServerCode({
    required String phone,
    required String code,
    required String deviceId,
  });
  Future<void> logout(String accessToken);
}

abstract class PhoneVerifier {
  Future<String> requestCode(String e164);
  Future<String> confirmCode({
    required String verificationId,
    required String smsCode,
  });
}

enum AuthStatus { idle, sending, codeSent, verifying, authenticated, error }

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthApi api,
    required PhoneVerifier verifier,
    required SessionStore store,
    this.deviceId = 'pending-device-id',
    this.resendCooldown = 60,
    this.maxAttempts = 5,
  })  : _api = api,
        _verifier = verifier,
        _store = store;

  final AuthApi _api;
  final PhoneVerifier _verifier;
  final SessionStore _store;

  final String deviceId;
  final int resendCooldown;
  final int maxAttempts;

  AuthStatus _status = AuthStatus.idle;
  String? _errorMessage;
  int _errorSeq = 0;
  String? _verificationId;
  String _digits10 = '';
  int _attempts = 0;
  bool _mustResend = false;
  bool _codeExpired = false;
  bool _newDeviceAlert = false;
  int _resendInSeconds = 0;
  AuthSession? _session;
  Timer? _timer;
  bool _disposed = false;

  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;
  int get errorSeq => _errorSeq;
  String get digits10 => _digits10;
  int get attempts => _attempts;
  int get attemptsLeft => (maxAttempts - _attempts).clamp(0, maxAttempts);
  bool get mustResend => _mustResend;
  bool get codeExpired => _codeExpired;
  bool get newDeviceAlert => _newDeviceAlert;
  int get resendInSeconds => _resendInSeconds;
  bool get canResend => _resendInSeconds <= 0;

  String _channel = 'firebase';
  String get channel => _channel;
  AuthSession? get session => _session;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated &&
      _session != null &&
      !_session!.isExpired;

  void consumeNewDeviceAlert() {
    _newDeviceAlert = false;
    _notify();
  }

  Future<void> sendOtp(String rawPhone) async {
    final digits = normalizeIndianPhone(rawPhone);
    if (digits == null) {
      _fail(vendorStringsHi['phoneError']!, AuthStatus.idle);
      return;
    }
    _digits10 = digits;
    _attempts = 0;
    _mustResend = false;
    _codeExpired = false;
    _errorMessage = null;
    _status = AuthStatus.sending;
    _notify();
    try {
      final e164 = '+91$digits';
      _channel = await _api.startOtp(e164);
      if (_channel != 'sms') {
        _verificationId = await _verifier.requestCode(e164);
      }
      _status = AuthStatus.codeSent;
      _startCooldown();
    } on ApiException catch (e) {
      _fail(
        e.isNetwork
            ? vendorStringsHi['networkError']!
            : '${vendorStringsHi['serverError']!} (${e.statusCode})',
        AuthStatus.error,
      );
    } catch (_) {
      _fail(vendorStringsHi['smsError']!, AuthStatus.error);
    }
    _notify();
  }

  Future<void> resend() async {
    if (!canResend || _digits10.isEmpty) return;
    await sendOtp(_digits10);
  }

  void expireCode() {
    _codeExpired = true;
    _fail(vendorStringsHi['codeExpired']!, AuthStatus.codeSent);
  }

  Future<void> confirm(String smsCode) async {
    if (_mustResend) {
      _fail(vendorStringsHi['tooManyAttempts']!, AuthStatus.codeSent);
      return;
    }
    if (_codeExpired) {
      _fail(vendorStringsHi['codeExpired']!, AuthStatus.codeSent);
      return;
    }
    final verificationId = _verificationId;
    if ((_channel != 'sms' && verificationId == null) || smsCode.length != 6) {
      _fail(vendorStringsHi['invalidCode']!, AuthStatus.codeSent);
      return;
    }
    _status = AuthStatus.verifying;
    _errorMessage = null;
    _notify();
    try {
      final AuthSession session;
      if (_channel == 'sms') {
        session = await _api.verifyServerCode(
          phone: '+91$_digits10',
          code: smsCode,
          deviceId: deviceId,
        );
      } else {
        final idToken = await _verifier.confirmCode(
          verificationId: verificationId!,
          smsCode: smsCode,
        );
        session = await _api.verifyOtp(
          idToken: idToken,
          deviceId: deviceId,
        );
      }
      // Vendor role gate: this app is vendors-only.
      if (session.role != 'vendor') {
        await _store.clear();
        _fail(vendorStringsHi['notVendor']!, AuthStatus.error);
        _notify();
        return;
      }
      await _store.saveSession(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        expiresAtIso: session.expiresAt.toIso8601String(),
        role: session.role,
      );
      _session = session;
      _newDeviceAlert = session.newDeviceAlert;
      _status = AuthStatus.authenticated;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        _fail(vendorStringsHi['networkError']!, AuthStatus.error);
      } else {
        _failAuthAttempt();
      }
    } catch (_) {
      _failAuthAttempt();
    }
    _notify();
  }

  void _failAuthAttempt() {
    _attempts += 1;
    if (_attempts >= maxAttempts) {
      _mustResend = true;
      _verificationId = null;
      _fail(vendorStringsHi['tooManyAttempts']!, AuthStatus.codeSent);
    } else {
      _fail(vendorStringsHi['invalidCode']!, AuthStatus.codeSent);
    }
  }

  Future<void> logout() async {
    final token = _session?.accessToken;
    if (token != null) {
      try {
        await _api.logout(token);
      } catch (_) {
        // Local wipe is authoritative — never strand a token on logout.
      }
    }
    await onLogoutCleanup?.call();
    await forceLogout();
  }

  /// Local-only wipe (no server call): used by [logout] and by the global
  /// 401/403 hook (revoked/suspended sessions must not call authed endpoints
  /// again — that would loop). [onLogoutCleanup] lets main.dart clear the
  /// offline outbox so the next login never inherits prior stops/cash.
  Future<void> Function()? onLogoutCleanup;

  Future<void> forceLogout() async {
    await _store.clear();
    _reset();
    _status = AuthStatus.idle;
    _notify();
  }

  Future<void> restoreSession() async {
    final access = await _store.readAccessToken();
    final refresh = await _store.readRefreshToken();
    final expiryIso = await _store.readExpiryIso();
    final role = await _store.readRole();
    if (access == null || refresh == null || expiryIso == null) {
      _status = AuthStatus.idle;
      _notify();
      return;
    }
    final expiresAt = DateTime.tryParse(expiryIso);
    if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
      await _store.clear();
      _status = AuthStatus.idle;
    } else {
      _session = AuthSession(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: expiresAt,
        role: role ?? 'vendor',
      );
      // Stored non-vendor session can never drive this app.
      if (_session!.role != 'vendor') {
        await _store.clear();
        _session = null;
        _status = AuthStatus.idle;
      } else {
        _status = AuthStatus.authenticated;
      }
    }
    _notify();
  }

  void clearError() {
    _errorMessage = null;
    _notify();
  }

  void _startCooldown() {
    _timer?.cancel();
    _resendInSeconds = resendCooldown;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_disposed) {
        t.cancel();
        return;
      }
      _resendInSeconds -= 1;
      if (_resendInSeconds <= 0) {
        _resendInSeconds = 0;
        t.cancel();
      }
      _notify();
    });
  }

  void _fail(String message, AuthStatus status) {
    _errorMessage = message;
    _errorSeq += 1;
    _status = status;
    _notify();
  }

  void _reset() {
    _timer?.cancel();
    _verificationId = null;
    _channel = 'firebase';
    _digits10 = '';
    _attempts = 0;
    _mustResend = false;
    _codeExpired = false;
    _newDeviceAlert = false;
    _resendInSeconds = 0;
    _session = null;
    _errorMessage = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
