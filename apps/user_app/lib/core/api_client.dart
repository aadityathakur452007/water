// F5 — API client over the Workers API (contract §3 conventions + §4 map).
//
// Envelope: success returns the decoded JSON; errors throw [ApiException]
// carrying code + status + retryAfter. Screens switch on `code` and show
// the offline banner on NETWORK (States.md), never raw status numbers.
// Authed calls carry Bearer access token + X-Device-Id; `Idempotency-Key`
// where the contract requires it (orders create/cancel/reschedule).
// TODO(F1): base URL from --dart-define; real token getter from SessionStore.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One place for the base URL (contract base; override at build time).
const String kApiBaseUrl = String.fromEnvironment(
  'SHODASHA_API_BASE',
  defaultValue: 'http://localhost:8787/v1',
);

/// Support number for never-dead-end paths (screens show it on 4xx walls).
const String kSupportPhone = '+91 93021 90067';

/// Thrown for every non-2xx / network failure.
class ApiException implements Exception {
  ApiException({
    required this.code,
    required this.message,
    required this.statusCode,
    this.retryAfterSeconds,
    this.details,
  });

  /// Contract §5 error code (VALIDATION, STALE_QUOTE, OVER_LIMIT,
  /// HOLD_BLOCKED, IDEMPOTENT_REPLAY, RATE_LIMITED, UNAUTH, NETWORK…).
  final String code;
  final String message;
  final int statusCode;
  final int? retryAfterSeconds;
  final Map<String, dynamic>? details;

  /// Offline / 5xx / timeout → offline banner (States.md network states).
  bool get isNetwork => code == 'NETWORK' || statusCode >= 500;

  @override
  String toString() => 'ApiException($code, $statusCode, $message)';
}

/// Thin typed client. One method per request; controllers own parsing.
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

  /// Static token (guest/simple wiring); [accessTokenGetter] wins when set.
  final String? accessToken;

  /// Live token supplier — wired to the AuthController so Bearer tracks the
  /// session without rebuilding every controller after login.
  final String? Function()? accessTokenGetter;

  /// X-Device-Id (fraud graph, SEC-F01).
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

  /// Single request path: send → decode → typed error. JSON body in/out.
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
    // Error envelope {error: {code, message, details}} — tolerant parse.
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

  // ── Addresses (§4.3) ──────────────────────────────────────────────────────
  Future<List<dynamic>> listAddresses() =>
      send('GET', '/addresses', authed: true) as Future<List<dynamic>>;

  Future<Map<String, dynamic>> createAddress(Map<String, dynamic> body) =>
      send('POST', '/addresses', body: body) as Future<Map<String, dynamic>>;

  Future<Map<String, dynamic>> patchAddress(
    String id,
    Map<String, dynamic> body,
  ) =>
      send('PATCH', '/addresses/$id', body: body)
          as Future<Map<String, dynamic>>;

  Future<void> deleteAddress(String id) =>
      send('DELETE', '/addresses/$id', authed: true);

  // ── Subscriptions / pause / skip (§4.5, EC-S) ─────────────────────────────
  Future<List<dynamic>> listSubscriptions() =>
      send('GET', '/subscriptions') as Future<List<dynamic>>;

  Future<Map<String, dynamic>> pauseSubscription(
    String id,
    String holdFrom,
    String holdTo,
  ) =>
      send('POST', '/subscriptions/$id/pause', body: {
        'hold_from': holdFrom,
        'hold_to': holdTo,
      }) as Future<Map<String, dynamic>>;

  Future<Map<String, dynamic>> resumeSubscription(
    String id,
    String preferredDate,
  ) =>
      send('POST', '/subscriptions/$id/resume', body: {
        'preferred_date': preferredDate,
      }) as Future<Map<String, dynamic>>;

  Future<Map<String, dynamic>> skipSubscriptionDay(String id, String date) =>
      send('POST', '/subscriptions/$id/skips', body: {'date': date})
          as Future<Map<String, dynamic>>;

  // ── Ledger / returns (§4.6) ───────────────────────────────────────────────
  Future<Map<String, dynamic>> ledgerMe() =>
      send('GET', '/ledger/me') as Future<Map<String, dynamic>>;

  /// POST /returns {qty, address_id} → request id + 10-working-day SLA.
  Future<Map<String, dynamic>> createReturn({
    required int qty,
    required String addressId,
  }) =>
      send('POST', '/returns', body: {
        'qty': qty,
        'address_id': addressId,
      }) as Future<Map<String, dynamic>>;

  // ── Complaints (§4.7, no-photo v1: reason codes + text ≤500) ──────────────
  Future<Map<String, dynamic>> createComplaint({
    required String orderId,
    required String reasonCode,
    required String text,
  }) =>
      send('POST', '/complaints', body: {
        'order_id': orderId,
        'reason_code': reasonCode,
        'text': text,
      }) as Future<Map<String, dynamic>>;

  Future<List<dynamic>> listComplaints() =>
      send('GET', '/complaints') as Future<List<dynamic>>;

  // ── Profile (§4.1 /auth/me) ───────────────────────────────────────────────
  Future<Map<String, dynamic>> me() =>
      send('GET', '/auth/me') as Future<Map<String, dynamic>>;

  Future<Map<String, dynamic>> patchMe(Map<String, dynamic> body) =>
      send('PATCH', '/auth/me', body: body) as Future<Map<String, dynamic>>;

  // ── Catalog (§4.2 — guest-callable, prices never walled) ─────────────────
  Future<Map<String, dynamic>> catalog() =>
      send('GET', '/catalog', authed: false) as Future<Map<String, dynamic>>;

  // ── Windows / quotes / orders (§4.2/§4.4 — 005-home-ux live checkout) ────
  /// GET /windows?date=YYYY-MM-DD&pincode= → {date, windows, serviceable}.
  Future<Map<String, dynamic>> windows({String? date, String? pincode}) =>
      send('GET', '/windows', query: {
        ...?date == null ? null : {'date': date},
        ...?pincode == null ? null : {'pincode': pincode},
      }, authed: false) as Future<Map<String, dynamic>>;

  /// POST /quotes {items:[{sku,qty}], e, address_id, window_start}.
  Future<Map<String, dynamic>> createQuote({
    required List<Map<String, dynamic>> items,
    required int empties,
    required String addressId,
    required String windowStart,
  }) =>
      send('POST', '/quotes', body: {
        'items': items,
        'e': empties,
        'address_id': addressId,
        'window_start': windowStart,
      }) as Future<Map<String, dynamic>>;

  /// POST /orders {items, e, address_id, window_start, quote_hash,
  /// payment_mode} + Idempotency-Key → 201 server-minted order.
  Future<Map<String, dynamic>> createOrder({
    required List<Map<String, dynamic>> items,
    required int empties,
    required String addressId,
    required String windowStart,
    required String quoteHash,
    required String paymentMode,
    required String idempotencyKey,
  }) =>
      send('POST', '/orders',
          body: {
            'items': items,
            'e': empties,
            'address_id': addressId,
            'window_start': windowStart,
            'quote_hash': quoteHash,
            'payment_mode': paymentMode,
          },
          idempotencyKey: idempotencyKey) as Future<Map<String, dynamic>>;

  /// GET /orders/{id} → order + tracker + bill (verify paid status here,
  /// never trust the client-side gateway callback alone).
  Future<Map<String, dynamic>> getOrder(String id) =>
      send('GET', '/orders/$id') as Future<Map<String, dynamic>>;

  // ── Subscriptions create (§4.5 — recurring buy path) ─────────────────────
  /// POST /subscriptions {address_id, qty, sku_mix, window, schedule_type,
  /// recurrence} → server-minted subscription.
  Future<Map<String, dynamic>> createSubscription({
    required String addressId,
    required int qty,
    required String skuMix,
    required String window,
    required String scheduleType,
    String recurrence = '',
  }) =>
      send('POST', '/subscriptions', body: {
        'address_id': addressId,
        'qty': qty,
        'sku_mix': skuMix,
        'window': window,
        'schedule_type': scheduleType,
        'recurrence': recurrence,
      }) as Future<Map<String, dynamic>>;

  // ── UPI intent (§4.4 — Razorpay order for the in-app gateway) ─────────────
  /// POST /payments/upi-intent {order_id} + Idempotency-Key →
  /// {payment, link, provider_ref (Razorpay order id)}.
  Future<Map<String, dynamic>> upiIntent({
    required String orderId,
    required String idempotencyKey,
  }) =>
      send('POST', '/payments/upi-intent',
          body: {'order_id': orderId},
          idempotencyKey: idempotencyKey) as Future<Map<String, dynamic>>;

  /// date → `YYYY-MM-DD` (hold_from/hold_to/skips date format).
  static String dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
