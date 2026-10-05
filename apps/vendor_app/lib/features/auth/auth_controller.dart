// Vendor auth state — access-code-only (028, spec §4). No OTP, no SMS round-trip,
// no guest: phone + admin-issued code → vendorCodeLogin → role gate
// (role must be `vendor`, else wiped with notVendor). Demo door stays as the
// server-gated QA fallback.

// ignore_for_file: prefer_initializing_formals
// (Ctor param `api` must stay public-named for main.dart wiring.)

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

/// Access codes are admin-issued (backend: 4–32 chars). Client checks the
/// floor only; the server is the enforcer (generic 401, no oracle).
bool isValidAccessCode(String raw) => raw.trim().length >= 4;

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

  /// Phase 5 §5.1: login instant for the 30-day cap banner. Defaults keep
  /// older fakes compiling; real stores persist it.
  Future<void> saveStartedAtIso(String iso) async {}
  Future<String?> readStartedAtIso() async => null;
}

class InMemorySessionStore implements SessionStore {
  String? _access;
  String? _refresh;
  String? _expiryIso;
  String? _role;
  String? _startedAtIso;

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
  Future<void> saveStartedAtIso(String iso) async {
    _startedAtIso = iso;
  }

  @override
  Future<String?> readStartedAtIso() async => _startedAtIso;

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _expiryIso = null;
    _role = null;
    _startedAtIso = null;
  }
}

abstract class AuthApi {
  /// POST /v1/auth/vendor/login `{phone, code, device:{id}}` → session
  /// (200; generic 401; 409 device-cap; 429 rate-limit).
  Future<AuthSession> vendorCodeLogin({
    required String phone,
    required String code,
    required String deviceId,
  });
  Future<void> logout(String accessToken);
  /// Phase 5 §5.1: POST /auth/refresh `{refresh_token, device:{id}}` →
  /// rotated pair (200; generic 401 on revoked/capped sessions).
  Future<AuthSession> refreshSession({
    required String refreshToken,
    required String deviceId,
  });
  /// POST /auth/demo `{phone, demo_code, device}` → session (QA demo door;
  /// server enforces the config flag + demo_codes row, closed in prod).
  Future<AuthSession> demoLogin({
    required String phone,
    required String code,
    required String deviceId,
  });
}

enum AuthStatus { idle, verifying, authenticated, error }

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthApi api,
    required SessionStore store,
    this.deviceId = 'pending-device-id',
  })  : _api = api,
        _store = store;

  final AuthApi _api;
  final SessionStore _store;

  final String deviceId;

  AuthStatus _status = AuthStatus.idle;
  String? _errorMessage;
  int _errorSeq = 0;
  bool _newDeviceAlert = false;
  AuthSession? _session;
  bool _disposed = false;

  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;
  int get errorSeq => _errorSeq;
  bool get newDeviceAlert => _newDeviceAlert;

  /// Phase 5 §5.1: login instant (UTC) for the 30-day cap banner. Null on
  /// pre-Phase-5 sessions (no banner — never guess).
  DateTime? _startedAt;
  DateTime? get sessionStartedAt => _startedAt;

  /// True when the absolute 30-day cap lands within 24h (banner, not a
  /// block — the shift continues; the cap logout still needs a re-login).
  bool get capExpiresSoon {
    final started = _startedAt;
    if (started == null) return false;
    final left = started.add(const Duration(days: 30)).difference(DateTime.now());
    return !left.isNegative && left < const Duration(hours: 24);
  }

  AuthSession? get session => _session;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated &&
      _session != null &&
      !_session!.isExpired;

  void consumeNewDeviceAlert() {
    _newDeviceAlert = false;
    _notify();
  }

  /// Access-code login: validate locally, POST vendor/login, gate the role,
  /// persist. Generic Hindi copy on 401 (no oracle); rate-limit + device-cap
  /// get their own lines. Returns true on success.
  Future<bool> codeLogin(String rawPhone, String rawCode) async {
    final digits = normalizeIndianPhone(rawPhone);
    if (digits == null) {
      _fail(vendorStringsHi['phoneError']!, AuthStatus.idle);
      return false;
    }
    final code = rawCode.trim();
    if (!isValidAccessCode(code)) {
      _fail(vendorStringsHi['codeError']!, AuthStatus.idle);
      return false;
    }
    _status = AuthStatus.verifying;
    _errorMessage = null;
    _notify();
    try {
      final session = await _api.vendorCodeLogin(
        phone: '+91$digits',
        code: code,
        deviceId: deviceId,
      );
      // Vendor role gate: this app is vendors-only.
      if (session.role != 'vendor') {
        await _store.clear();
        _fail(vendorStringsHi['notVendor']!, AuthStatus.error);
        return false;
      }
      await _store.saveSession(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        expiresAtIso: session.expiresAt.toIso8601String(),
        role: session.role,
      );
      await _stampStarted();
      _session = session;
      _newDeviceAlert = session.newDeviceAlert;
      _status = AuthStatus.authenticated;
      _notify();
      return true;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        _fail(vendorStringsHi['networkError']!, AuthStatus.error);
      } else if (e.statusCode == 401) {
        _fail(vendorStringsHi['invalidCredentials']!, AuthStatus.error);
      } else if (e.statusCode == 429) {
        _fail(vendorStringsHi['rateLimited']!, AuthStatus.error);
      } else if (e.statusCode == 409) {
        _fail(vendorStringsHi['deviceLimit']!, AuthStatus.error);
      } else {
        _fail(vendorStringsHi['serverError']!, AuthStatus.error);
      }
      return false;
    } catch (_) {
      _fail(vendorStringsHi['serverError']!, AuthStatus.error);
      return false;
    }
  }

  /// Demo login (no OTP): seeded phone + demo code → session. Same
  /// persistence + vendor role gate as the code path. Fails with a Hindi
  /// message when the server door is closed (prod default).
  Future<bool> demoLogin(String phone, String code) async {
    _status = AuthStatus.verifying;
    _errorMessage = null;
    _notify();
    try {
      final session = await _api.demoLogin(
        phone: phone.trim(),
        code: code.trim(),
        deviceId: deviceId,
      );
      if (session.role != 'vendor') {
        await _store.clear();
        _fail(vendorStringsHi['notVendor']!, AuthStatus.error);
        _notify();
        return false;
      }
      await _store.saveSession(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        expiresAtIso: session.expiresAt.toIso8601String(),
        role: session.role,
      );
      await _stampStarted();
      _session = session;
      _newDeviceAlert = session.newDeviceAlert;
      _status = AuthStatus.authenticated;
      _notify();
      return true;
    } on ApiException catch (e) {
      _fail(
        e.isNetwork ? vendorStringsHi['networkError']! : e.message,
        AuthStatus.error,
      );
      _notify();
      return false;
    } catch (_) {
      _fail(vendorStringsHi['serverError']!, AuthStatus.error);
      _notify();
      return false;
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
    _session = null;
    _startedAt = null;
    _newDeviceAlert = false;
    _errorMessage = null;
    _status = AuthStatus.idle;
    _notify();
  }

  /// End-of-session with an honest line on the login screen (cap expiry,
  /// revoked, suspended — the 401/403 hook path). forceLogout stays silent
  /// for the manual path. Outbox untouched: unsynced stops survive.
  Future<void> expireSession() async {
    await forceLogout();
    _errorMessage = vendorStringsHi['sessionExpired']!;
    _notify();
  }

  /// Phase 5 §5.1: silent renew with the stored refresh token. Returns true
  /// when the rotated pair is saved (caller retries the failed request
  /// once); false on any failure — status untouched, the caller force-
  /// logouts with the honest cap copy. Never throws.
  Future<bool> refreshSession() async {
    final refresh = await _store.readRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final session = await _api.refreshSession(
        refreshToken: refresh,
        deviceId: deviceId,
      );
      final role = _session?.role ?? 'vendor';
      await _store.saveSession(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        expiresAtIso: session.expiresAt.toIso8601String(),
        role: role,
      );
      _session = AuthSession(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        expiresAt: session.expiresAt,
        role: role,
        newDeviceAlert: _newDeviceAlert,
      );
      _status = AuthStatus.authenticated;
      _notify();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Login instant for the 30-day cap banner (rotation preserves the
  /// original cap, so this stamps once per login, never per refresh).
  Future<void> _stampStarted() async {
    _startedAt = DateTime.now().toUtc();
    try {
      await _store.saveStartedAtIso(_startedAt!.toIso8601String());
    } catch (_) {
      // Memory truth stands; the banner just skips this install.
    }
  }

  Future<void> restoreSession() async {
    final access = await _store.readAccessToken();
    final refresh = await _store.readRefreshToken();
    final expiryIso = await _store.readExpiryIso();
    final role = await _store.readRole();
    _startedAt = DateTime.tryParse(await _store.readStartedAtIso() ?? '');
    if (access == null || refresh == null || expiryIso == null) {
      _status = AuthStatus.idle;
      _notify();
      return;
    }
    final expiresAt = DateTime.tryParse(expiryIso);
    if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
      await _store.clear(); // session expired → logged-out state (States.md)
      _startedAt = null;
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
        _startedAt = null;
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

  void _fail(String message, AuthStatus status) {
    _errorMessage = message;
    _errorSeq += 1;
    _status = status;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
