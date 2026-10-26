// Customer auth for the Shodasha donor app (034).
//
// Contract:
//   POST /v1/auth/user/register {name, email?, phone, password, device}
//   POST /v1/auth/user/login    {phone, password, device}
//   POST /v1/auth/demo          {phone, demo_code, device} (server-gated QA)
//
// There is no customer phone-code sign-in. The retired routes answer 410 and no client
// method or screen may call them. Identity is a normalized Indian mobile plus
// a password; email is optional contact data, not a login proof.

// ignore_for_file: prefer_initializing_formals
// (Public ctor param names are required — tests + wiring construct this
// from other libraries, where private initializing formals are unusable.)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';

// English copy for v1 (ADR-120). Keys stay stable so a future Hinglish l10n
// pass can supply the same map without touching the screens.
const Map<String, String> authStringsHi = {
  'appName': 'Shodasha',
  'appTagline': 'Shodasha Mineral Water • RO+UV, lab-tested',
  'signInTitle': 'Welcome back',
  'signInSubtitle': 'Sign in with your mobile number and password.',
  'createTitle': 'Create your account',
  'createSubtitle': 'One account for every delivery.',
  'nameLabel': 'Name',
  'nameHint': 'Your name',
  'nameError': 'Enter a valid name (1–100 characters)',
  'emailLabel': 'Email (optional)',
  'emailHint': 'you@example.com',
  'emailError': 'Enter a valid email address, or leave it blank.',
  'phoneLabel': 'Mobile number',
  'phoneHint': '93021 90067',
  'phoneHelper': '10 digits only, starting 6–9',
  'phoneError':
      'Enter a valid 10-digit mobile number (digits only, starting 6–9)',
  'passwordLabel': 'Password',
  'passwordHint': '8+ characters, letter + number',
  'passwordError':
      'Use 8–128 characters with at least one letter and one digit.',
  'passwordRequired': 'Enter your password.',
  'confirmLabel': 'Confirm password',
  'confirmError': 'Passwords do not match.',
  'signInGo': 'Sign in',
  'createGo': 'Create account',
  'signingIn': 'Signing in…',
  'creating': 'Creating your account…',
  'forgotPassword': 'Forgot password? Contact support',
  'newHere': 'New here? Create account',
  'alreadyHere': 'Already have an account? Sign in',
  'terms':
      'By creating an account, you agree to Shodasha Terms & Privacy Policy.',
  'staffNumber': 'This number belongs to a staff account — contact support',
  'invalidCredentials': 'Mobile number or password is incorrect.',
  'accountExists': 'This number already has an account. Sign in.',
  'rateLimited': 'Too many attempts — wait a moment and try again',
  'rateLimitedWait': 'Too many attempts. Try again in',
  'serverError': 'Server problem — retry in a moment',
  'networkError': 'No internet — check your connection and try again',
  'validationError': 'Check your details and try again.',
  'sessionExpired': 'Your session expired. Sign in again.',
  'newDevice': 'New device detected — your old session stays safe',
  'notUser': 'This account is not for the customer app',
  'demoLogin': 'Try the demo (no registration)',
  'demoTitle': 'Demo login',
  'demoHint': 'Seeded demo account — for QA only',
  'demoCustomer': 'Fill demo customer',
  'demoGo': 'Log in with demo',
};

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

/// True when [raw] is a usable customer name (backend: 1–100 code points).
bool isValidUserName(String raw) {
  final name = raw.trim();
  final length = name.runes.length;
  return length > 0 && length <= 100;
}

/// True when [raw] is a valid email (034: any provider, optional on signup).
///
/// One `@`, a non-empty local part, a dot inside the domain, no whitespace,
/// max 254 chars. This mirrors the server's intent-check without pretending to
/// be an RFC parser.
bool isValidUserEmail(String raw) {
  final email = raw.trim();
  if (email.isEmpty || email.length > 254) return false;
  if (RegExp(r'\s').hasMatch(email)) return false;
  final at = email.indexOf('@');
  if (at <= 0 || at != email.lastIndexOf('@') || at == email.length - 1) {
    return false;
  }
  final domain = email.substring(at + 1);
  if (!domain.contains('.')) return false;
  if (domain.startsWith('.') || domain.endsWith('.')) return false;
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
}

/// True when [raw] satisfies the locked password policy (§6.2).
///
/// Length counts Unicode code points; passwords are never trimmed.
bool isValidPassword(String raw) {
  final length = raw.runes.length;
  if (length < 8 || length > 128) return false;
  return RegExp(r'[A-Za-z]').hasMatch(raw) && RegExp(r'\d').hasMatch(raw);
}

/// `9876543210` → `+91 ••••• 43210` (never show full digits on screen).
String maskPhone(String digits10) {
  final tail = digits10.length <= 5
      ? digits10
      : digits10.substring(digits10.length - 5);
  return '+91 ••••• $tail';
}

/// Session minted by register/login/demo.
@immutable
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.role,
    this.newDeviceAlert = false,
    this.verified = false,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String role;
  final bool newDeviceAlert;

  /// Doorstep-verification flag (server: always false until first PoD).
  final bool verified;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Persistence seam for the session (implemented with flutter_secure_storage
/// via `lib/core/session_store.dart`; [InMemorySessionStore] for tests).
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

/// Non-persistent fallback (tests). Never ship as the real store.
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

/// Backend seam: Workers API customer auth surface (034).
abstract class AuthApi {
  /// POST /auth/user/register → session.
  /// 400 VALIDATION, 409 ACCOUNT_EXISTS, 422 ROLE_RESERVED, 429 RATE_LIMITED.
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String deviceId,
  });

  /// POST /auth/user/login → session.
  /// 401 INVALID_CREDENTIALS (generic), 429 RATE_LIMITED.
  Future<AuthSession> login({
    required String phone,
    required String password,
    required String deviceId,
  });

  /// POST /auth/demo `{phone, demo_code, device}` → session (QA demo door;
  /// server enforces the config flag + demo_codes row, closed in prod).
  Future<AuthSession> demoLogin({
    required String phone,
    required String code,
    required String deviceId,
  });

  /// POST /auth/logout.
  Future<void> logout(String accessToken);

  /// POST /auth/refresh → rotated access + refresh tokens.
  Future<AuthSession> refresh({required String refreshToken});
}

/// Auth lifecycle: idle → verifying → authenticated.
/// Covers States.md form/action/auth states.
enum AuthStatus { idle, verifying, authenticated, error }

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthApi api,
    required SessionStore store,
    this.deviceId = 'pending-device-id',
    // Longer than ApiClient's 12s refresh timeout so a slow-but-alive
    // refresh is not cut off (and never mistaken for a dead session).
    this.restoreTimeout = const Duration(seconds: 20),
  }) : _api = api,
       _store = store;

  final AuthApi _api;
  final SessionStore _store;

  /// X-Device-Id (fraud graph, SEC-F01).
  final String deviceId;

  /// Upper bound for the cold-start secure-storage restore. A hung keychain
  /// must never strand the splash.
  final Duration restoreTimeout;

  AuthStatus _status = AuthStatus.idle;
  String? _errorMessage;
  String? _lastErrorCode;
  String? _sessionNotice;
  int _errorSeq = 0;
  bool _newDeviceAlert = false;
  AuthSession? _session;
  int _restoreGeneration = 0;
  bool _disposed = false;
  bool _loggingOut = false;
  Future<bool>? _recovering;
  DateTime? _rateLimitUntil;

  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;

  /// Last server/guard code (`ACCOUNT_EXISTS`, `ROLE_RESERVED`, `NETWORK`…).
  /// The screen uses it to pivot to sign-in on a duplicate signup.
  String? get lastErrorCode => _lastErrorCode;

  /// One-shot message shown by AuthGate after a forced session wipe.
  String? get sessionNotice => _sessionNotice;

  /// Bumps on every new error so screens can react to fresh failures.
  int get errorSeq => _errorSeq;
  bool get newDeviceAlert => _newDeviceAlert;

  AuthSession? get session => _session;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated &&
      _session != null &&
      !_session!.isExpired;

  /// True while the local logout wipe is in progress (UI busy state).
  bool get isLoggingOut => _loggingOut;

  /// Seconds left on a 429 wall (0 when none). Screens tick this locally.
  int get rateLimitSecondsRemaining {
    final until = _rateLimitUntil;
    if (until == null) return 0;
    final ms = until.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  /// Consume the new-device flag after home/profile has shown it.
  void consumeNewDeviceAlert() {
    _newDeviceAlert = false;
    _notify();
  }

  /// Clear the one-shot expiry notice after AuthGate has handed it to login.
  void clearSessionNotice() {
    if (_sessionNotice == null) return;
    _sessionNotice = null;
    _notify();
  }

  /// Create-only signup. An existing phone is never claimed or overwritten.
  Future<bool> register({
    required String name,
    String email = '',
    required String rawPhone,
    required String password,
    required String confirmPassword,
  }) async {
    _beginAttempt();
    if (!isValidUserName(name)) {
      _fail(authStringsHi['nameError']!, AuthStatus.idle);
      return false;
    }
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isNotEmpty && !isValidUserEmail(cleanEmail)) {
      _fail(authStringsHi['emailError']!, AuthStatus.idle);
      return false;
    }
    final digits = normalizeIndianPhone(rawPhone);
    if (digits == null) {
      _fail(authStringsHi['phoneError']!, AuthStatus.idle);
      return false;
    }
    if (!isValidPassword(password)) {
      _fail(authStringsHi['passwordError']!, AuthStatus.idle);
      return false;
    }
    if (password != confirmPassword) {
      _fail(authStringsHi['confirmError']!, AuthStatus.idle);
      return false;
    }
    return _attempt(
      () => _api.register(
        name: name.trim(),
        email: cleanEmail,
        phone: '+91$digits',
        password: password,
        deviceId: deviceId,
      ),
      isRegister: true,
    );
  }

  /// Sign in with mobile + password. Wrong phone and wrong password are
  /// deliberately indistinguishable.
  Future<bool> login({
    required String rawPhone,
    required String password,
  }) async {
    _beginAttempt();
    final digits = normalizeIndianPhone(rawPhone);
    if (digits == null) {
      _fail(authStringsHi['phoneError']!, AuthStatus.idle);
      return false;
    }
    if (password.isEmpty) {
      _fail(authStringsHi['passwordRequired']!, AuthStatus.idle);
      return false;
    }
    return _attempt(
      () => _api.login(
        phone: '+91$digits',
        password: password,
        deviceId: deviceId,
      ),
      isRegister: false,
    );
  }

  Future<bool> _attempt(
    Future<AuthSession> Function() call, {
    required bool isRegister,
  }) async {
    _status = AuthStatus.verifying;
    _errorMessage = null;
    _lastErrorCode = null;
    _rateLimitUntil = null;
    _notify();
    try {
      final session = await call();
      if (session.role != 'user') {
        await _store.clear();
        _fail(authStringsHi['notUser']!, AuthStatus.error);
        return false;
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
      _notify();
      return true;
    } on ApiException catch (e) {
      _handleApiError(e, isRegister: isRegister);
      return false;
    } catch (_) {
      _fail(authStringsHi['serverError']!, AuthStatus.error);
      return false;
    }
  }

  /// Demo login: server-gated QA door. Same persistence and role guard.
  Future<bool> demoLogin(String phone, String code) async {
    _beginAttempt();
    _status = AuthStatus.verifying;
    _notify();
    try {
      final session = await _api.demoLogin(
        phone: phone.trim(),
        code: code.trim(),
        deviceId: deviceId,
      );
      if (session.role != 'user') {
        await _store.clear();
        _fail(authStringsHi['notUser']!, AuthStatus.error);
        return false;
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
      _notify();
      return true;
    } on ApiException catch (e) {
      if (e.isOffline) {
        _fail(authStringsHi['networkError']!, AuthStatus.error);
      } else if (e.isServerError) {
        _fail(authStringsHi['serverError']!, AuthStatus.error);
      } else {
        _fail(
          e.message.isNotEmpty
              ? e.message
              : authStringsHi['invalidCredentials']!,
          AuthStatus.error,
        );
      }
      return false;
    } catch (_) {
      _fail(authStringsHi['serverError']!, AuthStatus.error);
      return false;
    }
  }

  /// Logout: wipe local session/prefs FIRST, then revoke server-side
  /// fire-and-forget with a 3s cap. A slow network must never delay the user
  /// leaving, and a failed revoke never strands a local token.
  /// Manual logout never shows expiry copy. Repeated taps are ignored.
  Future<void> logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    _notify();
    final token = _session?.accessToken;
    _restoreGeneration++;
    try {
      try {
        await _store.clear();
      } catch (_) {
        // Local state reset below is still authoritative.
      }
      await _clearUserPrefs();
      _reset();
      _sessionNotice = null;
      _status = AuthStatus.idle;
    } finally {
      _loggingOut = false;
      _notify();
    }
    if (token == null || token.isEmpty) return;
    unawaited(() async {
      try {
        await _api.logout(token).timeout(const Duration(seconds: 3));
      } catch (_) {
        // Best-effort revoke; the local session is already gone.
      }
    }());
  }

  /// One transparent refresh at most. Shares a single in-flight attempt so a
  /// burst of 401s rotates once, persists the rotated pair, and returns true.
  /// Never clears the local session before a successful refresh. Only an
  /// explicit auth rejection (401/403) ends the session; network, timeout,
  /// 429, 5xx and storage failures keep the refresh token for the next try.
  Future<bool> recoverSession() {
    final pending = _recovering;
    if (pending != null) return pending;
    final fut = _recoverSession();
    _recovering = fut;
    unawaited(
      fut.whenComplete(() {
        if (identical(_recovering, fut)) _recovering = null;
      }),
    );
    return fut;
  }

  Future<bool> _recoverSession() async {
    final gen = _restoreGeneration;
    try {
      final refresh = await _store.readRefreshToken();
      if (refresh == null || refresh.isEmpty) {
        if (gen != _restoreGeneration) return false;
        await forceLogout(sessionExpired: true);
        return false;
      }
      final rotated = await _api.refresh(refreshToken: refresh);
      if (gen != _restoreGeneration) return false;
      if (rotated.accessToken.isEmpty) {
        throw ApiException(
          code: 'UNKNOWN',
          message: 'Malformed refresh response',
          statusCode: 0,
        );
      }
      final role = rotated.role.isEmpty ? 'user' : rotated.role;
      await _store.saveSession(
        accessToken: rotated.accessToken,
        refreshToken: rotated.refreshToken.isEmpty
            ? refresh
            : rotated.refreshToken,
        expiresAtIso: rotated.expiresAt.toIso8601String(),
        role: role,
      );
      if (gen != _restoreGeneration) {
        // Logout raced the write: remove the resurrected pair, but never wipe
        // a newer login that already replaced the session.
        if (_session == null && _status == AuthStatus.idle) {
          try {
            await _store.clear();
          } catch (_) {
            // Best effort; the in-memory state is already logged out.
          }
        }
        return false;
      }
      _session = AuthSession(
        accessToken: rotated.accessToken,
        refreshToken: rotated.refreshToken.isEmpty
            ? refresh
            : rotated.refreshToken,
        expiresAt: rotated.expiresAt,
        role: role,
        newDeviceAlert: rotated.newDeviceAlert,
        verified: rotated.verified,
      );
      _sessionNotice = null;
      _status = AuthStatus.authenticated;
      _notify();
      return true;
    } catch (error) {
      if (gen != _restoreGeneration) return false;
      if (!_isAuthRejection(error)) {
        // Transient (offline/timeout/429/5xx/storage): keep the stored pair.
        // A later 401 or the next cold start can still rotate it.
        return false;
      }
      await forceLogout(sessionExpired: true);
      return false;
    }
  }

  static bool _isAuthRejection(Object error) =>
      error is ApiException &&
      (error.statusCode == 401 || error.statusCode == 403);

  /// Local-only wipe (no server call): the global 401/403 hook
  /// (revoked/suspended/expired — must not call authed endpoints again,
  /// that would loop).
  Future<void> forceLogout({bool sessionExpired = false}) async {
    _restoreGeneration++;
    try {
      await _store.clear();
    } catch (_) {
      // A keychain failure must not leave the in-memory session alive.
    }
    await _clearUserPrefs();
    _reset();
    _status = AuthStatus.idle;
    if (sessionExpired) {
      _sessionNotice = authStringsHi['sessionExpired'];
    }
    _notify();
  }

  /// Cold-start restore for [AuthGate]: valid session → authenticated.
  ///
  /// Bounded by [restoreTimeout]. A store that never answers must surface the
  /// login screen instead of an infinite splash. The generation guard
  /// discards an orphaned restore that completes after the timeout.
  ///
  /// Returns false only when restore itself failed/timed out. A normal
  /// "no session" or expired-session result returns true — the login screen
  /// is then the expected state, not an error.
  Future<bool> restoreSession() async {
    final gen = ++_restoreGeneration;
    try {
      await _restoreSession(gen).timeout(restoreTimeout);
      return true;
    } catch (_) {
      if (gen != _restoreGeneration) return false;
      _restoreGeneration++;
      _session = null;
      _status = AuthStatus.idle;
      _notify();
      return false;
    }
  }

  Future<void> _restoreSession(int gen) async {
    final access = await _store.readAccessToken();
    if (gen != _restoreGeneration) return;
    final refresh = await _store.readRefreshToken();
    if (gen != _restoreGeneration) return;
    final expiryIso = await _store.readExpiryIso();
    if (gen != _restoreGeneration) return;
    final role = await _store.readRole();
    if (gen != _restoreGeneration) return;
    if (access == null || refresh == null || expiryIso == null) {
      _status = AuthStatus.idle;
      _notify();
      return;
    }
    final expiresAt = DateTime.tryParse(expiryIso);
    if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
      // Access expired but refresh exists: try one rotation before forcing
      // login. The local session is not cleared until the refresh fails.
      final recovered = await recoverSession();
      if (gen != _restoreGeneration) return;
      if (recovered) return;
      // recoverSession already set the idle state + expiry notice.
      return;
    }
    _session = AuthSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expiresAt,
      role: role ?? 'user',
    );
    _status = AuthStatus.authenticated;
    _notify();
  }

  /// Clears a surfaced error (e.g. user edits a field again).
  void clearError() {
    if (_errorMessage == null && _lastErrorCode == null) return;
    _errorMessage = null;
    _lastErrorCode = null;
    _rateLimitUntil = null;
    _notify();
  }

  void _beginAttempt() {
    _errorMessage = null;
    _lastErrorCode = null;
    _rateLimitUntil = null;
  }

  void _handleApiError(ApiException e, {required bool isRegister}) {
    _lastErrorCode = e.code;
    if (e.statusCode == 429) {
      final wait = (e.retryAfterSeconds ?? 60).clamp(1, 3600);
      _rateLimitUntil = DateTime.now().add(Duration(seconds: wait));
      _fail(authStringsHi['rateLimited']!, AuthStatus.error);
      return;
    }
    if (isRegister && e.statusCode == 409) {
      _lastErrorCode = 'ACCOUNT_EXISTS';
      _fail(authStringsHi['accountExists']!, AuthStatus.error);
      return;
    }
    if (e.statusCode == 422 && e.code == 'ROLE_RESERVED') {
      _fail(authStringsHi['staffNumber']!, AuthStatus.error);
      return;
    }
    if (e.isOffline) {
      _fail(authStringsHi['networkError']!, AuthStatus.error);
      return;
    }
    if (e.isServerError) {
      _fail(authStringsHi['serverError']!, AuthStatus.error);
      return;
    }
    if (e.statusCode == 401) {
      _fail(authStringsHi['invalidCredentials']!, AuthStatus.error);
      return;
    }
    if (e.statusCode == 400 || e.statusCode == 422) {
      _fail(_validationCopy(e), AuthStatus.error);
      return;
    }
    _fail(
      e.message.isNotEmpty ? e.message : authStringsHi['validationError']!,
      AuthStatus.error,
    );
  }

  /// Map field details to our own copy; never dump raw server text.
  String _validationCopy(ApiException e) {
    final details = e.details;
    if (details != null) {
      if (details.containsKey('password')) {
        return authStringsHi['passwordError']!;
      }
      if (details.containsKey('email')) {
        return authStringsHi['emailError']!;
      }
      if (details.containsKey('phone')) {
        return authStringsHi['phoneError']!;
      }
      if (details.containsKey('name')) {
        return authStringsHi['nameError']!;
      }
    }
    return e.message.isNotEmpty ? e.message : authStringsHi['validationError']!;
  }

  Future<void> _clearUserPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('selected_address_id');
    } catch (_) {
      // Prefs wipe is best-effort — secure session already cleared.
    }
  }

  void _fail(String message, AuthStatus status) {
    _errorMessage = message;
    _errorSeq += 1;
    _status = status;
    _notify();
  }

  void _reset() {
    _session = null;
    _errorMessage = null;
    _lastErrorCode = null;
    _rateLimitUntil = null;
    _newDeviceAlert = false;
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
