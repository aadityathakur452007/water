// F2 — Auth state for the Shodasha user app (name+email+phone register).
//
// Backend contract: POST /v1/auth/user/register {name, email, phone,
// device:{id}} → 200 {access_token, refresh_token, role:"user", user_id,
// verified:false} / 400 (bad name/email/phone/device) / 422 ROLE_RESERVED
// (staff number) / 429. No OTP anywhere — phone is the identity, email a
// required contact field.
// Doorstep-verified: `verified` flips on first PoD in a later slice; until
// then display + future gating only.
//
// Guest-browse rule (user-flows flow 1): prices are NEVER walled behind
// login. The gate routes a valid session straight to home; without a
// session it shows the name+number screen, and its guest action drops into
// home as a guest. Register is enforced only at booking commit OR profile.

// ignore_for_file: prefer_initializing_formals
// (Public ctor param names are required — tests + wiring construct this
// from other libraries, where private initializing formals are unusable.)

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';

// TODO(F1): consolidate into lib/l10n/strings.dart (Hindi-first) and import
// it here. Do NOT create lib/l10n/ from F2 — F1 owns it.
const Map<String, String> authStringsHi = {
  'appName': 'Shodasha',
  'appTagline': 'Shodasha Mineral Water • RO+UV, lab-tested',
  'trustLine': 'RO+UV • Lab report • Refill Rs 28 / Jar Rs 30',
  'registerTitle': 'Naam, email aur mobile number likhein',
  'registerSubtitle': 'Naya account apne-aap ban jayega • OTP nahi chahiye',
  'nameLabel': 'Naam',
  'nameHint': 'Aapka naam',
  'nameError': 'Sahi naam likhein (1–100 akshar)',
  'emailLabel': 'Email',
  'emailHint': 'aap@gmail.com',
  'emailError': 'Sirf @gmail.com email chalega (jaise aap@gmail.com)',
  'phoneLabel': 'Mobile number',
  'phoneHint': '93021 90067',
  'phoneHelper': 'Sirf 10 ank, 6–9 se shuru',
  'phoneError': 'Sahi 10-digit mobile number likhein (sirf ank, 6–9 se shuru)',
  'registerGo': 'Shuru karein',
  'registering': 'Account ban raha hai…',
  'staffNumber':
      'Ye number staff account se juda hai — support se sampark karein',
  'rateLimited': 'Bahut koshish ho gayi — thodi der ruk kar try karein',
  'serverError': 'Server me dikkat — thodi der me retry karein',
  'networkError': 'Network me dikkat — dobara try karein',
  'newDevice': 'Naya device detect hua — purana session surakshit hai',
  'notUser': 'Ye account customer app ke liye nahi hai',
  'guestBrowse': 'Bina login ke daam dekhein',
  'guestNote': 'Daam dekhne ke liye login zaroori nahi',
  'demoLogin': 'Demo try karein (bina register)',
  'demoTitle': 'Demo login',
  'demoHint': 'Seeded demo account — QA ke liye, bina OTP',
  'demoCustomer': 'Demo customer bharein',
  'demoGo': 'Demo se login karein',
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

/// True when [raw] is a usable customer name (backend: 1–100 chars trimmed).
bool isValidUserName(String raw) {
  final name = raw.trim();
  return name.isNotEmpty && name.length <= 100;
}

/// True when [raw] is a valid @gmail.com address (backend: ≤254 chars,
/// ending with @gmail.com).
bool isValidUserEmail(String raw) {
  final email = raw.trim().toLowerCase();
  if (email.isEmpty || email.length > 254) return false;
  return RegExp(r'^[a-zA-Z0-9._%+-]+@gmail\.com$').hasMatch(email);
}

/// `9876543210` → `+91 ••••• 43210` (never show full digits on screen).
String maskPhone(String digits10) =>
    '+91 ••••• ${digits10.substring(digits10.length - 5)}';

/// Session minted by POST /auth/user/register (028).
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

/// Backend seam: Workers API user-auth surface (028).
abstract class AuthApi {
  /// POST /auth/user/register `{name, email, phone, device:{id}}` → session
  /// (200; 400 validation; 422 ROLE_RESERVED staff number; 429 rate-limit).
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
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
}

/// Auth lifecycle: idle → verifying → authenticated (no OTP states).
/// Covers States.md form/action/auth states.
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

  /// X-Device-Id (fraud graph, SEC-F01). TODO(F1): real device id provider.
  final String deviceId;

  AuthStatus _status = AuthStatus.idle;
  String? _errorMessage;
  int _errorSeq = 0;
  bool _newDeviceAlert = false;
  AuthSession? _session;
  bool _disposed = false;

  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;

  /// Bumps on every new error so screens can react to fresh failures.
  int get errorSeq => _errorSeq;
  bool get newDeviceAlert => _newDeviceAlert;

  AuthSession? get session => _session;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated &&
      _session != null &&
      !_session!.isExpired;

  /// Consume the new-device flag after home/profile has shown it.
  void consumeNewDeviceAlert() {
    _newDeviceAlert = false;
    _notify();
  }

  /// Name+email+phone register from [NameNumberScreen] (raw user input,
  /// normalized here). Returns true on success.
  Future<bool> registerNameNumber(
    String rawName,
    String rawEmail,
    String rawPhone,
  ) async {
    final name = rawName.trim();
    if (!isValidUserName(rawName)) {
      _fail(authStringsHi['nameError']!, AuthStatus.idle);
      return false;
    }
    final email = rawEmail.trim();
    if (!isValidUserEmail(rawEmail)) {
      _fail(authStringsHi['emailError']!, AuthStatus.idle);
      return false;
    }
    final digits = normalizeIndianPhone(rawPhone);
    if (digits == null) {
      _fail(authStringsHi['phoneError']!, AuthStatus.idle);
      return false;
    }
    _status = AuthStatus.verifying;
    _errorMessage = null;
    _notify();
    try {
      final session = await _api.register(
        name: name,
        email: email,
        phone: '+91$digits',
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
      if (e.isNetwork) {
        _fail(authStringsHi['networkError']!, AuthStatus.error);
      } else if (e.statusCode == 422) {
        _fail(authStringsHi['staffNumber']!, AuthStatus.error);
      } else if (e.statusCode == 429) {
        _fail(authStringsHi['rateLimited']!, AuthStatus.error);
      } else if ((e.statusCode == 400 || e.statusCode == 403) &&
          e.message.isNotEmpty) {
        // 400 validation + 403 role/suspended detail ride the server
        // message (generic, no oracle); anything else stays generic.
        _fail(e.message, AuthStatus.error);
      } else {
        _fail(authStringsHi['serverError']!, AuthStatus.error);
      }
      return false;
    } catch (_) {
      _fail(authStringsHi['serverError']!, AuthStatus.error);
      return false;
    }
  }

  /// Demo login (no OTP): seeded phone + demo code → session. Same
  /// persistence as the register path; rejects non-user roles so a vendor
  /// demo code can never drive the customer app. Fails loudly when the
  /// server door is closed (prod default).
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
      if (session.role != 'user') {
        await _store.clear();
        _fail(authStringsHi['notUser']!, AuthStatus.error);
        _notify();
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
      _fail(
        e.isNetwork ? authStringsHi['networkError']! : e.message,
        AuthStatus.error,
      );
      _notify();
      return false;
    } catch (_) {
      _fail(authStringsHi['serverError']!, AuthStatus.error);
      _notify();
      return false;
    }
  }

  /// Logout: revoke server-side (best-effort) + wipe local session (contract).
  /// Also clears user-scoped prefs (selected address) so the next
  /// login never inherits the previous user's delivery address.
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('selected_address_id');
    } catch (_) {
      // Prefs wipe is best-effort — secure session already cleared.
    }
    _reset();
    _status = AuthStatus.idle;
    _notify();
  }

  /// Local-only wipe (no server call): the global 401/403 hook
  /// (revoked/suspended/expired — must not call authed endpoints again,
  /// that would loop). Mirrors the vendor controller (Phase 4 §4.3).
  Future<void> forceLogout() async {
    await _store.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('selected_address_id');
    } catch (_) {
      // Prefs wipe is best-effort — secure session already cleared.
    }
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

  /// Clears a surfaced error (e.g. user edits a field again).
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

  void _reset() {
    _session = null;
    _errorMessage = null;
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
