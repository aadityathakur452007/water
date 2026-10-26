import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/features/orders/orders_controller.dart';
import 'package:shodasha_donor/features/orders/tracking_screen.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

http.Response _error(int status, String code) => _json({
  'error': {'code': code, 'message': 'failed'},
}, status);

ApiClient _api(
  http.Client client, {
  Duration ttl = const Duration(minutes: 5),
}) => ApiClient(
  client: client,
  baseUrl: 'http://127.0.0.1/v1',
  readCacheTtl: ttl,
);

void main() {
  group('public read cache', () {
    test('serves a hit inside the TTL without a second request', () async {
      var calls = 0;
      final api = _api(
        MockClient((request) async {
          calls += 1;
          return _json({'version': 'v1'});
        }),
      );

      final first = await api.catalog();
      final second = await api.catalog();

      expect(calls, 1);
      expect(second['version'], first['version']);
    });

    test('clearReadCache forces a refetch', () async {
      var calls = 0;
      final api = _api(
        MockClient((request) async {
          calls += 1;
          return _json({'version': 'v$calls'});
        }),
      );

      expect((await api.catalog())['version'], 'v1');
      api.clearReadCache();
      expect((await api.catalog())['version'], 'v2');
      expect(calls, 2);
    });
  });

  group('429 handling', () {
    test('a cacheable GET 429 is attempted exactly once', () async {
      var calls = 0;
      final api = _api(
        MockClient((request) async {
          calls += 1;
          return _error(429, 'RATE_LIMITED');
        }),
      );

      await expectLater(
        api.catalog(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 429)),
      );
      expect(calls, 1);
    });

    test('stale bytes are served instead of retrying a 429', () async {
      var calls = 0;
      final api = _api(
        MockClient((request) async {
          calls += 1;
          return calls == 1
              ? _json({'version': 'v1'})
              : _error(429, 'RATE_LIMITED');
        }),
        ttl: Duration.zero,
      );

      expect((await api.catalog(allowStale: true))['version'], 'v1');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect((await api.catalog(allowStale: true))['version'], 'v1');
      expect(calls, 2);
    });

    test('a GET 429 never retries even outside the cache path', () async {
      var calls = 0;
      final api = _api(
        MockClient((request) async {
          calls += 1;
          return _error(429, 'RATE_LIMITED');
        }),
      );

      await expectLater(
        api.send('GET', '/orders'),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
    });
  });

  group('stale fallback', () {
    test('serves stale on 5xx and on transport failure', () async {
      for (final failure in ['5xx', 'transport']) {
        var calls = 0;
        final api = _api(
          MockClient((request) async {
            calls += 1;
            if (calls == 1) return _json({'version': 'v1'});
            if (failure == '5xx') return _error(503, 'INTERNAL');
            throw http.ClientException('socket down');
          }),
          ttl: Duration.zero,
        );

        expect((await api.catalog(allowStale: true))['version'], 'v1');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(
          (await api.catalog(allowStale: true))['version'],
          'v1',
          reason: failure,
        );
        expect(calls, 2, reason: failure);
      }
    });

    test('without allowStale the failure is rethrown', () async {
      var calls = 0;
      final api = _api(
        MockClient((request) async {
          calls += 1;
          return calls == 1
              ? _json({'version': 'v1'})
              : _error(503, 'INTERNAL');
        }),
        ttl: Duration.zero,
      );

      await api.catalog();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await expectLater(api.catalog(), throwsA(isA<ApiException>()));
      expect(calls, 2);
    });
  });

  testWidgets('disposing mid-refresh never starts tracking', (tester) async {
    final repo = _GatedOrdersRepo([
      orderFromApi({
        'id': 'o1',
        'state': 'dispatched',
        'window_start': DateTime.utc(2026, 10, 26, 9).toIso8601String(),
      }),
    ]);
    final controller = _RecordingOrdersController(repo: repo);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TrackingScreen(controller: controller, orderId: 'o1'),
      ),
    );
    await tester.pump(); // run the post-frame refresh, which is gated

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    repo.gate.complete();
    await tester.pumpAndSettle();

    expect(controller.startTrackingCalls, 0);
  });
}

class _GatedOrdersRepo extends StubOrdersRepository {
  _GatedOrdersRepo(super.seed);

  final Completer<void> gate = Completer<void>();

  @override
  Future<Order> fetchOrder(String id) async {
    await gate.future;
    return super.fetchOrder(id);
  }
}

class _RecordingOrdersController extends OrdersController {
  _RecordingOrdersController({required super.repo});

  int startTrackingCalls = 0;

  @override
  void startTracking(String id) {
    startTrackingCalls += 1;
    super.startTracking(id);
  }
}
