// Phase 4 §4.3 — user client parity with the vendor client (copied pattern):
// single-flight GETs, bounded retry only when replay-safe, 401 hook fires.
// MockClient, no backend.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';

void main() {
  test('concurrent GETs join one socket (single-flight)', () async {
    var hits = 0;
    final mock = MockClient((req) async {
      hits += 1;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return http.Response(jsonEncode({'data': [], 'next_cursor': null}), 200);
    });
    final api = ApiClient(client: mock, deviceId: 't');
    final results = await Future.wait([
      api.send('GET', '/orders', query: {'limit': '20'}),
      api.send('GET', '/orders', query: {'limit': '20'}),
    ]);
    expect(hits, 1);
    expect(results.length, 2);
  });

  test('GET retries transient 500 then resolves', () async {
    var hits = 0;
    final mock = MockClient((req) async {
      hits += 1;
      if (hits == 1) return http.Response('boom', 500);
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final api = ApiClient(client: mock, deviceId: 't');
    final out = await api.send('GET', '/catalog', authed: false);
    expect((out as Map)['ok'], isTrue);
    expect(hits, 2);
  });

  test('POST without a key never retries (no double-apply)', () async {
    var hits = 0;
    final mock = MockClient((req) async {
      hits += 1;
      return http.Response('boom', 500);
    });
    final api = ApiClient(client: mock, deviceId: 't');
    await expectLater(
      api.send('POST', '/complaints', body: {'text': 'x'}),
      throwsA(isA<ApiException>()),
    );
    expect(hits, 1);
  });

  test('POST with a key retries the same key+body (single effect)', () async {
    var hits = 0;
    final seenKeys = <String?>[];
    final mock = MockClient((req) async {
      hits += 1;
      seenKeys.add(req.headers['Idempotency-Key']);
      if (hits == 1) return http.Response('boom', 500);
      return http.Response(jsonEncode({'order': {'id': 'o1'}}), 201);
    });
    final api = ApiClient(client: mock, deviceId: 't');
    final out = await api.send('POST', '/orders',
        body: {'items': []}, idempotencyKey: 'k-1');
    expect((out as Map)['order']['id'], 'o1');
    expect(hits, 2);
    expect(seenKeys, ['k-1', 'k-1']);
  });

  test('401 fires onUnauthorized once and throws', () async {
    var hooks = 0;
    final mock = MockClient(
        (req) async => http.Response(jsonEncode({'error': {'code': 'UNAUTH'}}), 401));
    final api = ApiClient(
      client: mock,
      deviceId: 't',
      onUnauthorized: () async {
        hooks += 1;
      },
    );
    await expectLater(
      api.send('GET', '/orders'),
      throwsA(isA<ApiException>().having(
          (e) => e.statusCode, 'status', 401)),
    );
    expect(hooks, 1);
  });

  test('429 is not the offline banner (distinct code + Retry-After)', () async {
    final mock = MockClient((req) async => http.Response(
        jsonEncode({'error': {'code': 'RATE_LIMITED'}}), 429,
        headers: {'retry-after': '7'}));
    final api = ApiClient(client: mock, deviceId: 't');
    try {
      await api.send('GET', '/catalog', authed: false);
      fail('must throw');
    } on ApiException catch (e) {
      expect(e.isNetwork, isFalse);
      expect(e.retryAfterSeconds, 7);
    }
  });
}
