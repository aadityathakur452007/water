import 'dart:convert';
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
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _riderUser;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  Map<String, dynamic>? get riderUser => _riderUser;
  bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;

  static const _tokenKey = 'rider_access_token_v1';
  static const _refreshTokenKey = 'rider_refresh_token_v1';
  static const _userKey = 'rider_user_data_v1';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_tokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    final userJson = prefs.getString(_userKey);
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
    String deviceId = 'rider-device-default',
  }) async {
    final url = Uri.parse('$baseUrl/v1/auth/rider/login');
    final res = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone.trim(),
        'name': name.trim(),
        // Vendor-issued sign-in code; the phone number alone is not enough.
        'code': code.trim(),
        'device': {'id': deviceId},
      }),
    );

    final data = _parseResponse(res);
    _accessToken = data['access_token'] as String?;
    _refreshToken = data['refresh_token'] as String?;
    
    // Fetch profile
    final meRes = await getRiderMe();
    _riderUser = meRes;

    final prefs = await SharedPreferences.getInstance();
    if (_accessToken != null) {
      await prefs.setString(_tokenKey, _accessToken!);
    }
    if (_refreshToken != null) {
      await prefs.setString(_refreshTokenKey, _refreshToken!);
    }
    if (_riderUser != null) {
      await prefs.setString(_userKey, jsonEncode(_riderUser));
    }

    return data;
  }

  Future<bool> refreshSession() async {
    final ref = _refreshToken;
    if (ref == null || ref.isEmpty) return false;
    try {
      final res = await _client.post(
        Uri.parse('$baseUrl/v1/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refresh_token': ref,
          'device': {'id': 'rider-device-default'},
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _accessToken = data['access_token'] as String?;
        final rotated = data['refresh_token'] as String?;
        if (rotated != null && rotated.isNotEmpty) {
          _refreshToken = rotated;
        }
        final prefs = await SharedPreferences.getInstance();
        if (_accessToken != null) {
          await prefs.setString(_tokenKey, _accessToken!);
        }
        if (_refreshToken != null) {
          await prefs.setString(_refreshTokenKey, _refreshToken!);
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
    var res = await request(_headers);
    if (res.statusCode == 401) {
      final refreshed = await refreshSession();
      if (refreshed) {
        res = await request(_headers);
      }
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userKey);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
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

