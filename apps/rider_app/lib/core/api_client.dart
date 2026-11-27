import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.retryAfterSeconds});
  final String message;
  final int? statusCode;
  final int? retryAfterSeconds;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    this.baseUrl = const String.fromEnvironment(
      'SHODASHA_API_BASE',
      defaultValue: 'https://water-ops.adityathakur452007.workers.dev',
    ),
    http.Client? client,
    FlutterSecureStorage? storage,
    this.onUnauthorized,
  }) : _client = client ?? http.Client(),
       _storage = storage ?? const FlutterSecureStorage();

  final String baseUrl;
  final http.Client _client;
  final FlutterSecureStorage _storage;
  VoidCallback? onUnauthorized;
  static const Duration _timeout = Duration(seconds: 12);

  String? _accessToken;
  String? _refreshToken;
  String _deviceId = 'rider-device-default';
  Map<String, dynamic>? _riderUser;
  Future<bool>? _refreshInFlight;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  Map<String, dynamic>? get riderUser => _riderUser;
  bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;

  static const _tokenKey = 'rider_access_token_v1';
  static const _refreshTokenKey = 'rider_refresh_token_v1';
  static const _userKey = 'rider_user_data_v1';
  static const _deviceIdKey = 'rider_device_id_v1';

  Future<void> init() async {
    var devId = await _storage.read(key: _deviceIdKey);
    var access = await _storage.read(key: _tokenKey);
    var refresh = await _storage.read(key: _refreshTokenKey);
    var userJson = await _storage.read(key: _userKey);

    // Seamless one-time migration from legacy plaintext SharedPreferences.
    try {
      final prefs = await SharedPreferences.getInstance();
      if (devId == null || devId.isEmpty) {
        final legacyDev = prefs.getString(_deviceIdKey);
        if (legacyDev != null && legacyDev.isNotEmpty) {
          devId = legacyDev;
          await _storage.write(key: _deviceIdKey, value: devId);
        }
      }
      if ((access == null || access.isEmpty) && prefs.containsKey(_tokenKey)) {
        access = prefs.getString(_tokenKey);
        refresh = prefs.getString(_refreshTokenKey);
        userJson = prefs.getString(_userKey);
        if (access != null) await _storage.write(key: _tokenKey, value: access);
        if (refresh != null) await _storage.write(key: _refreshTokenKey, value: refresh);
        if (userJson != null) await _storage.write(key: _userKey, value: userJson);
      }
      await prefs.remove(_deviceIdKey);
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_userKey);
    } catch (_) {
      // Best-effort legacy cleanup; secure storage remains authoritative.
    }

    if (devId == null || devId.isEmpty) {
      final rng = Random.secure();
      final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
      devId = 'rider-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      await _storage.write(key: _deviceIdKey, value: devId);
    }
    _deviceId = devId;
    _accessToken = access;
    _refreshToken = refresh;
    if (userJson != null) {
      try {
        _riderUser = jsonDecode(userJson) as Map<String, dynamic>;
      } catch (_) {
        _riderUser = null;
      }
    }
  }

  Future<Map<String, dynamic>> loginRider({
    required String phone,
    required String name,
    required String code,
    String? deviceId,
  }) async {
    final effectiveDeviceId = deviceId ?? _deviceId;
    final url = Uri.parse('$baseUrl/v1/auth/rider/login');
    final res = await _client
        .post(
          url,
          headers: {'Content-Type': 'application/json', 'X-Device-Id': effectiveDeviceId},
          body: jsonEncode({
            'phone': phone.trim(),
            'name': name.trim(),
            // Vendor-issued sign-in code; the phone number alone is not enough.
            'code': code.trim(),
            'device': {'id': effectiveDeviceId},
          }),
        )
        .timeout(_timeout);

    final data = _parseResponse(res);
    _accessToken = data['access_token'] as String?;
    _refreshToken = data['refresh_token'] as String?;

    // Fetch profile
    final meRes = await getRiderMe();
    _riderUser = meRes;

    if (_accessToken != null) {
      await _storage.write(key: _tokenKey, value: _accessToken!);
    }
    if (_refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: _refreshToken!);
    }
    if (_riderUser != null) {
      await _storage.write(key: _userKey, value: jsonEncode(_riderUser));
    }

    return data;
  }

  Future<bool> refreshSession() {
    final inflight = _refreshInFlight;
    if (inflight != null) return inflight;
    final fut = _doRefreshSession();
    _refreshInFlight = fut;
    fut.whenComplete(() {
      if (identical(_refreshInFlight, fut)) _refreshInFlight = null;
    });
    return fut;
  }

  Future<bool> _doRefreshSession() async {
    final ref = _refreshToken;
    if (ref == null || ref.isEmpty) return false;
    try {
      final res = await _client
          .post(
            Uri.parse('$baseUrl/v1/auth/refresh'),
            headers: {'Content-Type': 'application/json', 'X-Device-Id': _deviceId},
            body: jsonEncode({
              'refresh_token': ref,
              'device': {'id': _deviceId},
            }),
          )
          .timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _accessToken = data['access_token'] as String?;
        final rotated = data['refresh_token'] as String?;
        if (rotated != null && rotated.isNotEmpty) {
          _refreshToken = rotated;
        }
        if (_accessToken != null) {
          await _storage.write(key: _tokenKey, value: _accessToken!);
        }
        if (_refreshToken != null) {
          await _storage.write(key: _refreshTokenKey, value: _refreshToken!);
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _sendAuthed(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    var res = await request(_headers).timeout(_timeout);
    if (res.statusCode == 401) {
      final refreshed = await refreshSession();
      if (refreshed) {
        res = await request(_headers).timeout(_timeout);
      }
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      await logout();
      onUnauthorized?.call();
    }
    return _parseResponse(res);
  }

  Future<Map<String, dynamic>> getRiderMe() async {
    final url = Uri.parse('$baseUrl/v1/rider/me');
    return _sendAuthed((headers) => _client.get(url, headers: headers));
  }

  Future<Map<String, dynamic>> getDuty() async {
    final url = Uri.parse('$baseUrl/v1/rider/duty');
    return _sendAuthed((headers) => _client.get(url, headers: headers));
  }

  Future<Map<String, dynamic>> setDuty(String status) async {
    final url = Uri.parse('$baseUrl/v1/rider/duty');
    return _sendAuthed((headers) => _client.post(
      url,
      headers: headers,
      body: jsonEncode({'status': status}),
    ));
  }

  Future<Map<String, dynamic>> getTodayRoute() async {
    final url = Uri.parse('$baseUrl/v1/rider/routes/today');
    return _sendAuthed((headers) => _client.get(url, headers: headers));
  }

  Future<Map<String, dynamic>> completeDelivery({
    required String stopId,
    required String deliveryOtp,
    int emptiesCount = 0,
    int cash = 0,
  }) async {
    final url = Uri.parse('$baseUrl/v1/rider/stops/$stopId/complete');
    return _sendAuthed((headers) => _client.post(
      url,
      headers: headers,
      body: jsonEncode({
        'delivery_otp': deliveryOtp.trim(),
        'empties_count': emptiesCount,
        'cash': cash,
      }),
    ));
  }

  Future<Map<String, dynamic>> failDelivery({
    required String stopId,
    required String reasonCode,
    String note = '',
  }) async {
    final url = Uri.parse('$baseUrl/v1/rider/stops/$stopId/fail');
    return _sendAuthed((headers) => _client.post(
      url,
      headers: headers,
      body: jsonEncode({
        'reason_code': reasonCode,
        'note': note,
      }),
    ));
  }

  Future<Map<String, dynamic>> cancelDelivery({
    required String stopId,
    required String cancelOtp,
    String reason = 'CUSTOMER_UNREACHABLE',
  }) async {
    final url = Uri.parse('$baseUrl/v1/rider/stops/$stopId/cancel');
    return _sendAuthed((headers) => _client.post(
      url,
      headers: headers,
      body: jsonEncode({
        'cancel_otp': cancelOtp.trim(),
        'reason': reason.trim(),
      }),
    ));
  }

  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _riderUser = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _userKey);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Device-Id': _deviceId,
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Map<String, dynamic> _parseResponse(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return {};
      return jsonDecode(res.body) as Map<String, dynamic>;
    }

    String message = 'Server error (${res.statusCode})';
    try {
      final err = jsonDecode(res.body);
      if (err is Map) {
        if (err['error'] is Map && err['error']['message'] != null) {
          message = err['error']['message'].toString();
        } else if (err['detail'] != null) {
          message = err['detail'].toString();
        }
      }
    } catch (_) {}

    if (res.statusCode == 404 && message.contains('Stop not found')) {
      message = 'Incorrect delivery OTP. Please verify the code with the customer.';
    }

    int? retryAfter;
    final ra = res.headers['retry-after'];
    if (ra != null) {
      retryAfter = int.tryParse(ra.trim());
    }
    throw ApiException(message, statusCode: res.statusCode, retryAfterSeconds: retryAfter);
  }
}

