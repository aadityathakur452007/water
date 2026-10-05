// Phase 5 Split A — silent refresh, duty truth, discovery poll, accept.
// MockClient + fakes, no backend.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/features/auth/auth_controller.dart';
import 'package:vendor_app/features/duty/duty_controller.dart';
import 'package:vendor_app/features/route/route_controller.dart';

class _FakeAuthApi implements AuthApi {
  _FakeAuthApi({this.refreshed});

  /// Tokens the fake refresh endpoint rotates to (null → 401).
  final AuthSession? refreshed;
  int refreshCalls = 0;

  AuthSession _session() => AuthSession(
        accessToken: 'a0',
        refreshToken: 'r0',
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
        role: 'vendor',
      );

  @override
  Future<AuthSession> vendorCodeLogin({
    required String phone,
    required String code,
    required String deviceId,
  }) async =>
      _session();

  @override
  Future<AuthSession> demoLogin({
    required String phone,
    required String code,
    required String deviceId,
  }) async =>
      _session();

  @override
  Future<void> logout(String accessToken) async {}

  @override
  Future<AuthSession> refreshSession({
    required String refreshToken,
    required String deviceId,
  }) async {
    refreshCalls += 1;
    final s = refreshed;
    if (s == null) {
      throw ApiException(code: 'UNAUTH', message: 'expired', statusCode: 401);
    }
    return s;
  }
}

AuthSession _rotated() => AuthSession(
      accessToken: 'a1',
      refreshToken: 'r1',
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      role: 'vendor',
    );

Future<void> _seedStore(SessionStore store) => store.saveSession(
      accessToken: 'a0',
      refreshToken: 'r0',
      expiresAtIso:
          DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
      role: 'vendor',
    );

void main() {
  group('refreshSession', () {
    test('rotated pair saved, request retries once', () async {
      final api = _FakeAuthApi(refreshed: _rotated());
      final store = InMemorySessionStore();
      final c =
          AuthController(api: api, store: store, deviceId: 'd1');
      await _seedStore(store);
      expect(await c.refreshSession(), isTrue);
      expect(api.refreshCalls, 1);
      expect(c.session?.accessToken, 'a1');
      expect(c.isAuthenticated, isTrue);
    });

    test('failed refresh returns false, session untouched', () async {
      final api = _FakeAuthApi(refreshed: null);
      final c = AuthController(
          api: api, store: InMemorySessionStore(), deviceId: 'd1');
      expect(await c.refreshSession(), isFalse);
      expect(c.session, isNull);
    });

    test('cap banner only with known start', () async {
      // Fresh login → far from cap → no banner.
      final c = AuthController(
          api: _FakeAuthApi(refreshed: _rotated()),
          store: InMemorySessionStore(),
          deviceId: 'd1');
      await c.codeLogin('+919302190067', 'code-1234');
      expect(c.capExpiresSoon, isFalse);

      // Pre-Phase-5 session (no start persisted) → never guess.
      final store2 = InMemorySessionStore();
      final c2 = AuthController(
          api: _FakeAuthApi(refreshed: _rotated()),
          store: store2,
          deviceId: 'd1');
      await _seedStore(store2);
      await c2.restoreSession();
      expect(c2.capExpiresSoon, isFalse);

      // Start 29d6h ago → cap within 24h → banner.
      final store = InMemorySessionStore();
      await _seedStore(store);
      await store.saveStartedAtIso(DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 29, hours: 6))
          .toIso8601String());
      final c3 = AuthController(
          api: _FakeAuthApi(refreshed: _rotated()),
          store: store,
          deviceId: 'd1');
      await c3.restoreSession();
      expect(c3.capExpiresSoon, isTrue);
    });
  });

  group('client 401 hook', () {
    test('first-401 renews then retries once (no logout)', () async {
      var hits = 0;
      var renewed = 0;
      var logouts = 0;
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/orders')) {
          hits += 1;
          if (hits == 1) {
            return http.Response(
                jsonEncode({'error': {'code': 'UNAUTH'}}), 401);
          }
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response('not found', 404);
      });
      final api = ApiClient(
        client: mock,
        deviceId: 't',
        tryRefresh: () async {
          renewed += 1;
          return true;
        },
        onUnauthorized: () async {
          logouts += 1;
        },
      );
      final out = await api.send('GET', '/orders');
      expect((out as Map)['data'], isEmpty);
      expect(hits, 2);
      expect(renewed, 1);
      expect(logouts, 0);
    });

    test('failed renew fires logout once; 403 never renews', () async {
      var renewed = 0;
      var logouts = 0;
      final mock = MockClient((req) async => http.Response(
          jsonEncode({'error': {'code': 'UNAUTH'}}),
          req.url.path.endsWith('/forbidden') ? 403 : 401));
      final api = ApiClient(
        client: mock,
        deviceId: 't',
        tryRefresh: () async {
          renewed += 1;
          return false;
        },
        onUnauthorized: () async {
          logouts += 1;
        },
      );
      await expectLater(api.send('GET', '/orders'),
          throwsA(isA<ApiException>()));
      await expectLater(api.send('GET', '/forbidden'),
          throwsA(isA<ApiException>()));
      expect(renewed, 1); // 403 skipped the hook
      expect(logouts, 2);
    });
  });

  group('duty truth', () {
    ApiClient dutyApi({required bool onDuty, int repooled = 0}) {
      final mock = MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/vendor/profile')) {
          return http.Response(
              jsonEncode({'user_id': 'v1', 'on_duty': onDuty}), 200);
        }
        if (p.endsWith('/vendor/routes/today')) {
          return http.Response(
              jsonEncode({
                'route': {'id': 'r1'},
                'stops': [
                  {'id': 's1', 'seq': 1, 'status': 'pending'}
                ],
                'loading': {'take_fulls': 2, 'expect_empties': 1},
                'skip': [],
              }),
              200);
        }
        if (p.endsWith('/vendor/duty')) {
          return http.Response(
              jsonEncode(
                  {'duty_on': false, 'since': null, 'repooled': repooled}),
              200);
        }
        return http.Response('not found', 404);
      });
      return ApiClient(client: mock, deviceId: 't');
    }

    test('stale route does not imply duty (server off → OFF)', () async {
      final c = DutyController(api: dutyApi(onDuty: false));
      await c.load();
      expect(c.onDuty, isFalse);
      expect(c.state, DutyState.off);
      expect(c.stopsToday, 1); // route facts still load
    });

    test('server on-duty shows ON; duty-off surfaces repooled', () async {
      final c = DutyController(api: dutyApi(onDuty: true));
      await c.load();
      expect(c.onDuty, isTrue);
      expect(c.state, DutyState.on);
    });

    test('duty-off reports repooled count', () async {
      final c = DutyController(api: dutyApi(onDuty: true, repooled: 3));
      await c.setDuty(false);
      expect(c.onDuty, isFalse);
      expect(c.lastRepooled, 3);
    });
  });

  group('discovery + accept', () {
    test('poll fires on interval, stops on demand', () async {
      var routeHits = 0;
      final mock = MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/vendor/routes/today')) {
          routeHits += 1;
          return http.Response(
              jsonEncode(
                  {'route': null, 'stops': [], 'loading': {}, 'skip': []}),
              200);
        }
        if (p.endsWith('/vendor/placed')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response('not found', 404);
      });
      final c =
          RouteController(api: ApiClient(client: mock, deviceId: 't'));
      c.startDiscovery(interval: const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(routeHits, greaterThanOrEqualTo(2));
      c.stopDiscovery();
      final frozen = routeHits;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(routeHits, frozen);
      c.dispose();
    });

    test('accept reloads route + pool with honest notice', () async {
      var acceptHits = 0;
      final mock = MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/accept') && req.method == 'POST') {
          acceptHits += 1;
          return http.Response(
              jsonEncode({'order_id': 'o9', 'stop_id': 's9', 'version': 1}),
              200);
        }
        if (p.endsWith('/vendor/routes/today')) {
          return http.Response(
              jsonEncode({
                'route': {'id': 'r1'},
                'stops': [],
                'loading': {},
                'skip': []
              }),
              200);
        }
        if (p.endsWith('/vendor/placed')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response('not found', 404);
      });
      final c =
          RouteController(api: ApiClient(client: mock, deviceId: 't'));
      expect(await c.acceptPlaced('o9'), isTrue);
      expect(acceptHits, 1);
      expect(c.acceptNotice, contains('route'));
      c.dispose();
    });
  });
}
