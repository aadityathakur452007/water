// Vendor API client — mirrors user_app ApiClient (send/headers/envelope),
// trimmed to the vendor surface (contract §4.7 + §4.1/§4.10). Money on the
// wire is integer paise; the server computes everything.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const String kApiBaseUrl = String.fromEnvironment(
  'SHODASHA_API_BASE',
  defaultValue: 'http://localhost:8787/v1',
);

const String kSupportPhone = '+91 93021 90067';

class ApiException implements Exception {
  ApiException({
    required this.code,
    required this.message,
    required this.statusCode,
    this.retryAfterSeconds,
    this.details,
  });

  final String code;
  final String message;
  final int statusCode;
  final int? retryAfterSeconds;
  final Map<String, dynamic>? details;

  bool get isNetwork => code == 'NETWORK' || statusCode >= 500;

  @override
  String toString() => 'ApiException($code, $statusCode, $message)';
}

class ApiClient {
  ApiClient({
    http.Client? client,
    this.baseUrl = kApiBaseUrl,
    this.accessToken,
    this.accessTokenGetter,
    this.deviceId = 'unknown-device',
  }) : _http = client ?? http.Client();

  final http.Client _http;
  final String baseUrl;
  final String? accessToken;
  final String? Function()? accessTokenGetter;
  final String deviceId;

  String? get _token => accessTokenGetter?.call() ?? accessToken;

  Map<String, String> _headers({required bool authed, String? idempotencyKey}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'X-Device-Id': deviceId,
    };
    final token = _token;
    if (authed && token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    if (idempotencyKey != null) h['Idempotency-Key'] = idempotencyKey;
    return h;
  }

  Uri _uri(String path, Map<String, String>? query) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: base.path.endsWith('/')
          ? '${base.path}${path.substring(1)}'
          : '${base.path}$path',
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  Future<dynamic> send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool authed = true,
    String? idempotencyKey,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final uri = _uri(path, query);
    final http.Response resp;
    try {
      final req = http.Request(method, uri)
        ..headers.addAll(
          _headers(authed: authed, idempotencyKey: idempotencyKey),
        );
      if (body != null) req.body = jsonEncode(body);
      resp = await _http
          .send(req)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        code: 'NETWORK',
        message: 'Request timed out',
        statusCode: 0,
      );
    } catch (_) {
      throw ApiException(
        code: 'NETWORK',
        message: 'Network unavailable',
        statusCode: 0,
      );
    }
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return null;
      return jsonDecode(utf8.decode(resp.bodyBytes));
    }
    var code = 'UNKNOWN';
    var message = 'Request failed (${resp.statusCode})';
    Map<String, dynamic>? details;
    int? retryAfter;
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final err = decoded['error'];
        if (err is Map<String, dynamic>) {
          code = (err['code'] as String?) ?? code;
          message = (err['message'] as String?) ?? message;
          final d = err['details'];
          if (d is Map<String, dynamic>) details = d;
        }
      }
    } on FormatException {
      // Non-JSON error body → keep defaults.
    }
    final ra = resp.headers['retry-after'];
    if (ra != null) retryAfter = int.tryParse(ra);
    throw ApiException(
      code: code,
      message: message,
      statusCode: resp.statusCode,
      retryAfterSeconds: retryAfter,
      details: details,
    );
  }

  // ── Vendor ops (§4.7) ────────────────────────────────────────────────
  // NOTE: each method awaits [send] then casts the VALUE — never cast the
  // Future itself (`as Future<Map>` is a runtime type error in Dart).
  Future<Map<String, dynamic>> setDuty(bool on) async {
    final raw = await send('POST', '/vendor/duty', body: {'on': on});
    return (raw as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> todayRoute({String? date}) async {
    final raw = await send(
      'GET',
      '/vendor/routes/today',
      query: date == null ? null : {'date': date},
    );
    return (raw as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getStop(String id) async {
    final raw = await send('GET', '/vendor/stops/$id');
    return (raw as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> postTriple({
    required String stopId,
    required Map<String, dynamic> triple,
    required String idempotencyKey,
  }) async {
    final raw = await send('POST', '/vendor/stops/$stopId/triple',
        body: triple, idempotencyKey: idempotencyKey);
    return (raw as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> postPod({
    required String stopId,
    required Map<String, dynamic> pod,
  }) async {
    final raw = await send('POST', '/vendor/stops/$stopId/pod', body: pod);
    return (raw as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> syncBatch(
      List<Map<String, dynamic>> items) async {
    final raw = await send('POST', '/vendor/sync', body: {'items': items});
    return (raw as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> earnings({String? shift}) async {
    final raw = await send(
      'GET',
      '/vendor/earnings',
      query: shift == null ? null : {'shift': shift},
    );
    return (raw as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> verifyComplaint({
    required String complaintId,
    required bool agree,
    required String note,
  }) async {
    final raw = await send('POST', '/complaints/$complaintId/verify', body: {
      'agree': agree,
      'note': note,
    });
    return (raw as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> vendorCheckQuality({
    required String incidentId,
    required bool agree,
    required String check,
    required String note,
  }) async {
    final raw = await send('POST', '/quality/$incidentId/vendor-check', body: {
      'agree': agree,
      'check': check,
      'note': note,
    });
    return (raw as Map<String, dynamic>);
  }

  // ── Profile ──────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> me() async {
    final raw = await send('GET', '/auth/me');
    return (raw as Map<String, dynamic>);
  }
}
