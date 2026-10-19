// F5 — Session persistence + device identity (F2's [SessionStore] seam,
// now implemented with flutter_secure_storage — dep is in pubspec).
//
// Secure Storage holds access/refresh/expiry/role; keychain-backed on
// Android (ENC service). Device id: random UUID persisted in secure storage
// so the fraud graph sees a stable X-Device-Id per install (SEC-F01).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../features/auth/auth_controller.dart';

/// Real [SessionStore] over flutter_secure_storage.
class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kAccess = 'shodasha.access';
  static const _kRefresh = 'shodasha.refresh';
  static const _kExpiry = 'shodasha.expiry';
  static const _kRole = 'shodasha.role';

  @override
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String expiresAtIso,
    required String role,
  }) async {
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
    await _storage.write(key: _kExpiry, value: expiresAtIso);
    await _storage.write(key: _kRole, value: role);
  }

  @override
  Future<String?> readAccessToken() => _storage.read(key: _kAccess);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _kRefresh);

  @override
  Future<String?> readExpiryIso() => _storage.read(key: _kExpiry);

  @override
  Future<String?> readRole() => _storage.read(key: _kRole);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kExpiry);
    await _storage.delete(key: _kRole);
  }
}

/// Stable per-install device id (X-Device-Id). First boot mints a UUID and
/// persists it; every later boot reads the same value.
Future<String> loadOrCreateDeviceId() async {
  const storage = FlutterSecureStorage();
  const key = 'shodasha.device_id';
  final existing = await storage.read(key: key);
  if (existing != null && existing.isNotEmpty) return existing;
  final id = const Uuid().v4();
  await storage.write(key: key, value: id);
  return id;
}
