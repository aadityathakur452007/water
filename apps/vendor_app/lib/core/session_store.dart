// Session persistence + device identity — mirrors user_app
// SecureSessionStore (keys shared so tooling stays identical).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../features/auth/auth_controller.dart';

class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kAccess = 'shodasha.access';
  static const _kRefresh = 'shodasha.refresh';
  static const _kExpiry = 'shodasha.expiry';
  static const _kRole = 'shodasha.role';
  static const _kStarted = 'shodasha.session_started';

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
  Future<void> saveStartedAtIso(String iso) =>
      _storage.write(key: _kStarted, value: iso);

  @override
  Future<String?> readStartedAtIso() => _storage.read(key: _kStarted);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kExpiry);
    await _storage.delete(key: _kRole);
    await _storage.delete(key: _kStarted);
  }
}

Future<String> loadOrCreateDeviceId() async {
  const storage = FlutterSecureStorage();
  const key = 'shodasha.device_id';
  final existing = await storage.read(key: key);
  if (existing != null && existing.isNotEmpty) return existing;
  final id = const Uuid().v4();
  await storage.write(key: key, value: id);
  return id;
}
