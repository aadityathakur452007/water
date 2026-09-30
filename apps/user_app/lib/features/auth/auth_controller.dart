// F2 — Auth state for the Shodasha user app (branch 004-user-app-build).
//
// Backend contract: Feature_docs/backend/api-contract.md §4.1
// (otp/start → 202, otp/verify → session, refresh rotation, logout) and
// Feature_docs/synthesis/user-flows.md flow 1 (prices visible WITHOUT login;
// OTP only at booking commit OR profile).
//
// Wiring notes (F1 owns pubspec.yaml + google-services.json):
// - firebase_auth / flutter_secure_storage are NOT in pubspec.yaml yet, so a
//   hard import would break `flutter analyze`. [PhoneVerifier], [AuthApi] and
//   [SessionStore] are the seams — F1 plugs the real Firebase + Secure Storage
//   implementations in without touching callers.
// - Firebase is invoked ONLY inside user actions (send / resend / confirm),
//   never at import or build time, so missing google-services.json cannot
//   break compilation.

// ignore_for_file: prefer_initializing_formals
// (Public ctor param names are required — tests + F1 wiring construct this
// from other libraries, where private initializing formals are unusable.)

import 'dart:async';

import 'package:flutter/foundation.dart';

// TODO(F1): consolidate into lib/l10n/strings.dart (Hindi-first) and import
// it here. Do NOT create lib/l10n/ from F2 — F1 owns it.
const Map<String, String> authStringsHi = {
  'appName': 'Shodasha',
  'appTagline': 'Shodasha Mineral Water • RO+UV, lab-tested',
  'trustLine': 'RO+UV • Lab report • Refill Rs 28 / Jar Rs 30',
  'loginTitle': 'Mobile number se login karein',
  'loginSubtitle': 'OTP se verify hoga • naya account apne-aap ban jayega',
  'phoneLabel': 'Mobile number',
  'phoneHint': '98765 43210',
  'phoneHelper': '10 ank, 6–9 se shuru ho',
  'phoneError': 'Sahi 10-digit mobile number likhein (6–9 se shuru)',
  'sendOtp': 'OTP bhejein',
  'sending': 'OTP bheja ja raha hai…',
  'guestBrowse': 'Bina login ke daam dekhein',
  'guestNote': 'Daam dekhne ke liye login zaroori nahi',
  'otpTitle': 'OTP daalein',
  'otpSentTo': '6-digit OTP bheja gaya:',
  'verify': 'Verify karein',
  'verifying': 'Verify ho raha hai…',
  'resend': 'OTP dobara bhejein',
  'tooManyAttempts': '5 baar galat OTP — naya OTP mangwayein',
  'codeExpired': 'OTP expired ho gaya — naya OTP bhejein',
  'invalidCode': 'Galat OTP — dobara try karein',
  'networkError': 'Network me dikkat — dobara try karein',
  'newDevice': 'Naya device detect hua — purana session surakshit hai',
  'editNumber': 'Number badlein',
};

/// Dynamic Hindi copy (kept as functions so screens share one phrasing).
String resendInHi(int seconds) => 'Naya OTP $seconds second me milega';
String attemptsHi(int left) => '$left prayas bache (kul 5)';

/// Strips spaces/dashes/+91/0 variants → 10-digit subscriber number.
///
/// Accepts: `9876543210`, `+91 98765 43210`, `919876543210`, `09876543210`.
/// Returns null when the input is not a valid Indian mobile number
/// (`[6-9]` followed by 9 digits — covers the `+91[6-9]········` rule).
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

/// True when [raw] normalizes to a valid Indian mobile number.
bool isValidIndianPhone(String raw) => normalizeIndianPhone(raw) != null;

/// `9876543210` → `+91 ••••• 43210` (never show full digits on screen).
String maskPhone(String digits10) =>
    '+91 ••••• ${digits10.substring(digits10.length - 5)}';

/// Session minted by POST /auth/otp/verify (contract §4.1).
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

/// Persistence seam for the session (F1: implement with flutter_secure_storage
/// via `lib/core/session_store.dart`; until then [InMemorySessionStore]).
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

/// Non-persistent fallback (tests + pre-F1 wiring). Never ship as the real store.
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

/// Backend seam: Workers API auth surface (contract §4.1).
/// TODO(F1): implement over the real base URL with dart:io (no new pub deps).
abstract class AuthApi {
  /// POST /auth/otp/start — 202 + `{sent_to_masked, resend_after_s}`.
  Future<void> startOtp(String e164);
  /// POST /auth/otp/verify `{firebase_id_token, device}` → session.
  Future<AuthSession> verifyOtp({
    required String idToken,
    required String deviceId,
  });
  /// POST /auth/logout.
  Future<void> logout(String accessToken);
}

/// Firebase phone seam (mirrors FirebaseAuth.verifyPhoneNumber callbacks).
/// TODO(F1): implement with firebase_auth once the dep + google-services.json
/// land. Called ONLY from user actions below — never at build/import time.
abstract class PhoneVerifier {
  /// Sends the SMS via Firebase, returns verificationId.
  Future<String> requestCode(String e164);
  /// Confirms [smsCode] against [verificationId], returns Firebase idToken.
  Future<String> confirmCode({
    required String verificationId,
    required String smsCode,
  });
}

/// Auth lifecycle: idle → sending → codeSent → verifying → authenticated.
/// Covers States.md form/action/auth states (incl. expired + logged-out).
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

  /// X-Device-Id (fraud graph, SEC-F01). TODO(F1): real device id provider.
  final String deviceId;

  /// Resend cooldown seconds (contract: resend_after_s; default 60).
  final int resendCooldown;

  /// Wrong-code attempts before a forced resend (contract: verify 5/code).
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

  /// Bumps on every new error so screens can react (e.g. clear OTP boxes).
  int get errorSeq => _errorSeq;
  String get digits10 => _digits10;
  int get attempts => _attempts;
  int get attemptsLeft => (maxAttempts - _attempts).clamp(0, maxAttempts);
  bool get mustResend => _mustResend;
  bool get codeExpired => _codeExpired;
  bool get newDeviceAlert => _newDeviceAlert;
  int get resendInSeconds => _resendInSeconds;
  bool get canResend => _resendInSeconds <= 0;
  AuthSession? get session => _session;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated &&
      _session != null &&
      !_session!.isExpired;

  /// Consume the new-device flag after F3's home/profile has shown it.
  void consumeNewDeviceAlert() {
    _newDeviceAlert = false;
    _notify();
  }

  /// First send from [PhoneScreen] (raw user input, normalized here).
  Future<void> sendOtp(String rawPhone) async {
    final digits = normalizeIndianPhone(rawPhone);
    if (digits == null) {
      _fail(authStringsHi['phoneError']!, AuthStatus.idle);
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
      await _api.startOtp(e164); // 202; server rate-limits (SEC-A02)
      _verificationId = await _verifier.requestCode(e164); // Firebase SMS
      _status = AuthStatus.codeSent;
      _startCooldown();
    } catch (_) {
      _fail(authStringsHi['networkError']!, AuthStatus.error);
    }
    _notify();
  }

  /// Resend after cooldown / max-attempts / expiry. No-op while cooling down.
  Future<void> resend() async {
    if (!canResend || _digits10.isEmpty) return;
    await sendOtp(_digits10);
  }

  /// Marks the code expired (wrong-code path from Firebase / timeout).
  /// UI shows the expired-code path + resend CTA (ui-checklist: Verifying).
  void expireCode() {
    _codeExpired = true;
    _fail(authStringsHi['codeExpired']!, AuthStatus.codeSent);
  }

  /// Confirms the 6-digit [smsCode] → Firebase idToken → our otp/verify.
  Future<void> confirm(String smsCode) async {
    if (_mustResend) {
      _fail(authStringsHi['tooManyAttempts']!, AuthStatus.codeSent);
      return;
    }
    if (_codeExpired) {
      _fail(authStringsHi['codeExpired']!, AuthStatus.codeSent);
      return;
    }
    final verificationId = _verificationId;
    if (verificationId == null || smsCode.length != 6) {
      _fail(authStringsHi['invalidCode']!, AuthStatus.codeSent);
      return;
    }
    _status = AuthStatus.verifying;
    _errorMessage = null;
    _notify();
    try {
      final idToken = await _verifier.confirmCode(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final session = await _api.verifyOtp(
        idToken: idToken,
        deviceId: deviceId,
      );
      await _store.saveSession(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        expiresAtIso: session.expiresAt.toIso8601String(),
        role: session.role,
      );
      _session = session;
      _newDeviceAlert = session.newDeviceAlert;
      _status = AuthStatus.authenticated;
    } catch (_) {
      _attempts += 1;
      if (_attempts >= maxAttempts) {
        _mustResend = true;
        _verificationId = null; // old code is dead — force resend
        _fail(authStringsHi['tooManyAttempts']!, AuthStatus.codeSent);
      } else {
        _fail(authStringsHi['invalidCode']!, AuthStatus.codeSent);
      }
    }
    _notify();
  }

  /// Logout: revoke server-side (best-effort) + wipe local session (contract).
  Future<void> logout() async {
    final token = _session?.accessToken;
    if (token != null) {
      try {
        await _api.logout(token);
      } catch (_) {
        // Local wipe is authoritative — never strand a token on logout.
      }
    }
    await _store.clear();
    _reset();
    _status = AuthStatus.idle;
    _notify();
  }

  /// Cold-start restore for [AuthGate]: valid session → authenticated.
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
      await _store.clear(); // session expired → logged-out state (States.md)
      _status = AuthStatus.idle;
    } else {
      _session = AuthSession(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: expiresAt,
        role: role ?? 'user',
      );
      _status = AuthStatus.authenticated;
    }
    _notify();
  }

  /// Clears a surfaced error (e.g. user edits the phone field again).
  void clearError() {
    _errorMessage = null;
    _notify();
  }

  @visibleForTesting
  void debugExpireCooldown() {
    _timer?.cancel();
    _resendInSeconds = 0;
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
