// S8 — Profile identity: GET /v1/auth/me (read) + PATCH /v1/auth/me (edit).
//
// States.md coverage: initial, loading (skeleton), loaded, error (message +
// retry), guest/empty (log-in CTA), submitting (save spinner), validation
// error (inline), success (sheet pops + snackbar), unauthorized (session
// copy; the transport's 401/403 hook wipes the local session).
//
// Wallet / ledger / payments / returns belong to S7. This slice never fetches
// money data — ProfileScreen only exposes navigation callbacks for them.

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';

/// Copy shared by the controller and the edit sheet (English v1, per ADR-120).
const String kProfileOfflineError = 'No internet — please try again.';
const String kProfileServerError =
    'Server is having trouble — please try again.';
const String kProfileSessionError = 'Session expired. Please log in again.';
const String kProfileLoadError = 'Could not load your profile.';
const String kProfileSaveError =
    'Could not save your profile. Please try again.';
const String kProfilePhoneError = 'Enter a valid 10-digit mobile number.';
const String kProfileEmailError = 'Enter a valid @gmail.com address.';

/// Optional profile fields: empty is allowed (the server clears them).
/// Backend rule (auth_service.update_me) is ported verbatim:
/// `^(\+91|91|0)?[6-9]\d{9}$` / `^[a-zA-Z0-9._%+-]+@gmail\.com$`.
String? validateProfilePhone(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  const pattern = r'^(\+91|91|0)?[6-9]\d{9}$';
  return RegExp(pattern).hasMatch(value) ? null : kProfilePhoneError;
}

String? validateProfileEmail(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return null;
  const pattern = r'^[a-zA-Z0-9._%+-]+@gmail\.com$';
  return RegExp(pattern).hasMatch(value) ? null : kProfileEmailError;
}

enum ProfileStatus { initial, loading, loaded, error }

class ProfileController extends ChangeNotifier {
  // ignore: prefer_initializing_formals — public ctor name is the API seam.
  ProfileController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  ProfileStatus _status = ProfileStatus.initial;
  Map<String, dynamic>? _user;
  String? _errorMessage;
  bool _saving = false;
  bool _disposed = false;

  /// User boundary: bumped by [reset]; async completions from a previous
  /// account are discarded.
  int _generation = 0;

  ProfileStatus get status => _status;
  Map<String, dynamic>? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get saving => _saving;

  /// GET /auth/me. Best-effort identity read — money data is S7's job.
  Future<void> load() async {
    if (_status == ProfileStatus.loading) return;
    _status = ProfileStatus.loading;
    _errorMessage = null;
    _notify();
    final gen = _generation;
    try {
      final res = await _api.me();
      if (gen != _generation) return; // reset mid-flight (logout/user switch)
      _user = (res['user'] as Map<String, dynamic>?) ?? res;
      _status = ProfileStatus.loaded;
    } on ApiException catch (e) {
      if (gen != _generation) return;
      _status = ProfileStatus.error;
      _errorMessage = _loadError(e);
    } catch (_) {
      if (gen != _generation) return;
      _status = ProfileStatus.error;
      _errorMessage = kProfileLoadError;
    }
    _notify();
  }

  /// User boundary: drops the cached identity so the next account never sees
  /// the previous user's name/phone.
  void reset() {
    _generation++;
    _user = null;
    _status = ProfileStatus.initial;
    _errorMessage = null;
    _saving = false;
    _notify();
  }

  /// PATCH /auth/me {name, phone, email}. Returns the server message on
  /// failure (passthrough: real validation copy beats a generic wall), null
  /// on success. The sheet owns the inline field validation.
  Future<String?> updateProfile({
    required String name,
    required String phone,
    required String email,
  }) async {
    if (_saving) return null;
    _saving = true;
    _notify();
    final gen = _generation;
    try {
      final res = await _api.patchMe({
        'name': name.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
      });
      if (gen != _generation) return null;
      _user = (res['user'] as Map<String, dynamic>?) ?? res;
      return null;
    } on ApiException catch (e) {
      if (e.code == 'NETWORK') return kProfileOfflineError;
      if (e.statusCode >= 500) return kProfileServerError;
      if (e.statusCode == 401 || e.statusCode == 403) {
        return kProfileSessionError;
      }
      if (e.message.isNotEmpty) return e.message;
      return kProfileSaveError;
    } catch (_) {
      return kProfileSaveError;
    } finally {
      _saving = false;
      _notify();
    }
  }

  String _loadError(ApiException e) {
    if (e.code == 'NETWORK') return kProfileOfflineError;
    if (e.statusCode >= 500) return kProfileServerError;
    if (e.statusCode == 401 || e.statusCode == 403) {
      return kProfileSessionError;
    }
    return kProfileLoadError;
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
