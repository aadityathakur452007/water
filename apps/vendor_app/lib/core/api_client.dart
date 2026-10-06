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
    this.onUnauthorized,
    this.tryRefresh,
  })  : _http = client ?? http.Client() {
    // Fail fast in debug on cleartext prod builds: the release pipeline
    // always passes an https SHODASHA_API_BASE. Localhost stays allowed.
    assert(
      baseUrl.startsWith('https://') ||
          baseUrl.contains('localhost') ||
          baseUrl.contains('127.0.0.1') ||
          baseUrl.contains('10.0.2.2'),
      'ApiClient baseUrl must be https (or loopback for dev): $baseUrl',
    );
  }

  final http.Client _http;
  final String baseUrl;
  final String? accessToken;
  final String? Function()? accessTokenGetter;
  final String deviceId;

  /// Fired once per 401/403 response (suspended / revoked / expired).
  /// The app clears the session and returns to login (never loops: the
  /// hook must not itself call an authed endpoint).
  final Future<void> Function()? onUnauthorized;

  /// Phase 5 §5.1: silent renew — tried once on the first 401 of a call
  /// (never on 403/suspended). True → the failed request retries once
  /// with the rotated Bearer; false/null → [onUnauthorized] fires.
  final Future<bool> Function()? tryRefresh;

  /// In-flight GET dedupe (single-flight): two callers, one socket.
  /// Cleanup uses then/onError (never whenComplete): whenComplete mints a
  /// derived future that rethrows unlistened and trips test-zone guards.
  final Map<String, Future<dynamic>> _inflight = {};

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

  /// Single request path: send → decode → typed error. JSON body in/out.
  ///
  /// Resilience (minimum requests, no retry storms):
  /// - GETs are single-flighted (concurrent duplicates join one socket).
  /// - Retried (max 3, backoff 500ms·2ⁿ + jitter, honors Retry-After): only
  ///   NETWORK/timeout, 408, 429, 5xx — and POSTs only when an
  ///   [idempotencyKey] is present or [retryPost] is set (caller guarantees
  ///   the operation is replay-safe: same key + same body, or per-item keys
  ///   as in sync batches). Never retries 400/401/403/404/409.
  /// - 401/403 fires [onUnauthorized] once (session revoked/suspended).
  ///   Phase 5 §5.1: a first-401 runs [tryRefresh] once and retries the
  ///   request with the rotated token (silent renew, no mid-shift bounce);
  ///   [attemptRefresh]=false opts out (the refresh call itself — that
  ///   would recurse).
  Future<dynamic> send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool authed = true,
    String? idempotencyKey,
    bool retryPost = false,
    bool attemptRefresh = true,
    Duration timeout = const Duration(seconds: 12),
  }) {
    if (method == 'GET') {
      final key = 'GET ${_uri(path, query)}';
      final flying = _inflight[key];
      if (flying != null) return flying;
      final fut = _sendWithRetry(
        method, path,
        body: body,
        query: query,
        authed: authed,
        idempotencyKey: idempotencyKey,
        retryPost: retryPost,
        attemptRefresh: attemptRefresh,
        timeout: timeout,
      );
      _inflight[key] = fut;
      unawaited(fut.then<void>(
        (_) {
          _inflight.remove(key);
        },
        onError: (_) {
          _inflight.remove(key);
        },
      ));
      return fut;
    }
    return _sendWithRetry(
      method, path,
      body: body,
      query: query,
      authed: authed,
      idempotencyKey: idempotencyKey,
      retryPost: retryPost,
      attemptRefresh: attemptRefresh,
      timeout: timeout,
    );
  }

  bool _retryable(Object e) {
    if (e is! ApiException) return false;
    if (e.code == 'NETWORK') return true;
    return e.statusCode == 408 || e.statusCode == 429 || e.statusCode >= 500;
  }

  Future<dynamic> _sendWithRetry(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool authed = true,
    String? idempotencyKey,
    bool retryPost = false,
    bool attemptRefresh = true,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    // POST without an idempotency key (or explicit replay-safety) must never
    // auto-retry: a timeout may mean the server already applied it
    // (triple/PoD would double-apply).
    final retryableMethod = method == 'GET' ||
        method == 'DELETE' ||
        idempotencyKey != null ||
        retryPost;
    var attempt = 0;
    var refreshed = false;
    while (true) {
      attempt += 1;
      try {
        return await _sendOnce(
          method, path,
          body: body,
          query: query,
          authed: authed,
          idempotencyKey: idempotencyKey,
          timeout: timeout,
        );
      } on ApiException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 403) {
          // Silent renew first (401 only, once per call): the rotated
          // Bearer may save the shift. 403/suspended never refreshes.
          if (e.statusCode == 401 &&
              attemptRefresh &&
              !refreshed &&
              await tryRefresh?.call() == true) {
            refreshed = true;
            continue;
          }
          await onUnauthorized?.call();
        }
        final canRetry = retryableMethod && attempt < 3 && _retryable(e);
        if (!canRetry) rethrow;
        var waitMs = 500 * (1 << (attempt - 1));
        final serverWait = (e.retryAfterSeconds ?? 0) * 1000;
        if (serverWait > waitMs) waitMs = serverWait;
        if (waitMs > 10000) waitMs = 10000;
        // Full jitter: spread retries so fleets don't thunder.
        final jitter = DateTime.now().microsecond % (waitMs + 1);
        await Future<void>.delayed(Duration(milliseconds: jitter));
      }
    }
  }

  Future<dynamic> _sendOnce(
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

  /// 015: placed pool for the Pull button (placed orders, no route yet).
  Future<List<dynamic>> placedPool({int limit = 20}) async {
    final raw = await send('GET', '/vendor/placed',
        query: {'limit': '$limit'});
    if (raw is List<dynamic>) return raw;
    return ((raw as Map<String, dynamic>)['data'] as List?) ?? [];
  }

  /// Phase 5 §5.5: self-accept one zone-scoped placed order (single-touch
  /// placed→assigned + route/stop; replay returns the existing stop).
  /// No idempotency key: a timeout surfaces retry copy instead of risking
  /// a blind auto-retry (server replay is idempotent, the UX is explicit).
  Future<Map<String, dynamic>> acceptPlaced(String orderId) async {
    final raw = await send('POST', '/vendor/placed/$orderId/accept');
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

  /// F2: doorstep cash → money truth. Replay-safe server-side
  /// (deterministic stop+amount scope), so background retry is allowed.
  Future<Map<String, dynamic>> postStopCash({
    required String stopId,
    required int amountPaise,
  }) async {
    final raw = await send('POST', '/vendor/stops/$stopId/cash',
        body: {'amount': amountPaise}, retryPost: true);
    return (raw as Map<String, dynamic>);
  }

  /// GET /invoices/{orderId} → {amount_due, ...}. The cash button posts the
  /// live remainder (server 422s anything above it as OVERPAY).
  Future<Map<String, dynamic>> invoiceApi(String orderId) async =>
      (await send('GET', '/invoices/$orderId')) as Map<String, dynamic>;

  /// F8: empty-jar pickup for a return (vendor's own route only).
  Future<Map<String, dynamic>> pickupReturn({
    required String returnId,
    required int emptiesCollected,
    required int capsMissing,
  }) async {
    final raw = await send('POST', '/returns/$returnId/pickup',
        body: {'empties_collected': emptiesCollected, 'caps_missing': capsMissing},
        retryPost: true);
    return (raw as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> syncBatch(
      List<Map<String, dynamic>> items) async {
    // Background flush waits longer than interactive calls (Workers cold
    // start + D1 bind on a big batch); attempts stay capped at 3. Replay is
    // safe: dedupe is per-item inside the batch (each item has its own key).
    final raw = await send('POST', '/vendor/sync',
        body: {'items': items},
        retryPost: true,
        timeout: const Duration(seconds: 60));
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

  // ── Server profile + slots (011_port, Slice 1) ─────────────────────────
  Future<Map<String, dynamic>> vendorProfile() async {
    final raw = await send('GET', '/vendor/profile');
    return (raw as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> saveVendorProfile(
      Map<String, String> fields) async {
    final raw = await send('PATCH', '/vendor/profile', body: fields);
    return (raw as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> vendorSlots() async {
    final raw = await send('GET', '/vendor/slots');
    return (raw as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> saveVendorSlots(
      Map<String, bool> slots) async {
    final raw = await send('PUT', '/vendor/slots', body: {'slots': slots});
    return (raw as Map<String, dynamic>);
  }

  // ── Customers + complaint queue (011_port, derived — no new backend) ───
  Future<Map<String, dynamic>> vendorCustomers({String? date}) async {
    final raw = await send(
      'GET',
      '/vendor/customers',
      query: date == null ? null : {'date': date},
    );
    return (raw as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> vendorComplaints() async {
    final raw = await send('GET', '/vendor/complaints');
    return (raw as Map<String, dynamic>);
  }
}
