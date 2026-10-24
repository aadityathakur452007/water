import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/core/auth_impls.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

http.Response _unauth() => _json({
  'error': {'code': 'UNAUTH', 'message': 'Session expired.'},
}, 401);

void main() {
  test('single-flight separates different bearer tokens', () async {
    var token = 'token-a';
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return _json({'ok': true});
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.example.test/v1',
      accessTokenGetter: () => token,
    );

    final first = api.send('GET', '/auth/me');
    token = 'token-b';
    final second = api.send('GET', '/auth/me');

    await Future.wait([first, second]);
    expect(calls, 2);
  });

  test('single-flight coalesces the same bearer token', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return _json({'ok': true});
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.example.test/v1',
      accessTokenGetter: () => 'token-a',
    );

    await Future.wait([
      api.send('GET', '/auth/me'),
      api.send('GET', '/auth/me'),
    ]);
    expect(calls, 1);
  });

  test('authed 401 refreshes once and retries with the new token', () async {
    var token = 'expired';
    var refreshCalls = 0;
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      if (request.headers['authorization'] == 'Bearer fresh') {
        return _json({'ok': true});
      }
      return _unauth();
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.example.test/v1',
      accessTokenGetter: () => token,
      onUnauthorized: () async {
        refreshCalls += 1;
        token = 'fresh';
        return true;
      },
    );

    final result = await api.send('GET', '/auth/me');

    expect(result, {'ok': true});
    expect(refreshCalls, 1);
    expect(requests, 2);
  });

  test('a second 401 after refresh is final (no loop)', () async {
    var token = 'expired';
    var refreshCalls = 0;
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      token = 'still-rejected';
      return _unauth();
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.example.test/v1',
      accessTokenGetter: () => token,
      onUnauthorized: () async {
        refreshCalls += 1;
        return true;
      },
    );

    await expectLater(
      api.send('GET', '/auth/me'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(refreshCalls, 1);
    expect(requests, 2);
  });

  test('failed recovery rethrows the original 401 without retrying', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      return _unauth();
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.example.test/v1',
      accessTokenGetter: () => 'expired',
      onUnauthorized: () async => false,
    );

    await expectLater(
      api.send('GET', '/auth/me'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(requests, 1);
  });

  test('auth-management calls can suppress the refresh hook', () async {
    var hookCalls = 0;
    final client = MockClient((request) async => _unauth());
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.example.test/v1',
      accessTokenGetter: () => 'captured-access',
      onUnauthorized: () async {
        hookCalls += 1;
        return true;
      },
    );

    await expectLater(
      api.send('POST', '/auth/logout', authed: true, notifyUnauthorized: false),
      throwsA(isA<ApiException>()),
    );
    expect(hookCalls, 0);
  });

  test('unauthed 401 never calls the refresh hook', () async {
    var hookCalls = 0;
    final client = MockClient((request) async => _unauth());
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.example.test/v1',
      onUnauthorized: () async {
        hookCalls += 1;
        return true;
      },
    );

    await expectLater(
      api.send(
        'POST',
        '/auth/user/login',
        body: {'phone': '+919876543210'},
        authed: false,
      ),
      throwsA(isA<ApiException>()),
    );
    expect(hookCalls, 0);
  });

  test('refreshSession posts the stored contract with no bearer', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return _json({
        'access_token': 'new-access',
        'refresh_token': 'new-refresh',
        'expires_at': DateTime.now()
            .add(const Duration(minutes: 30))
            .toIso8601String(),
      });
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.example.test/v1',
      deviceId: 'device-1',
      accessToken: 'old-access',
    );

    final raw = await api.refreshSession(refreshToken: 'old-refresh');

    expect(raw['access_token'], 'new-access');
    expect(seen.method, 'POST');
    expect(seen.url.path, '/v1/auth/refresh');
    expect(seen.headers['authorization'], isNull);
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['refresh_token'], 'old-refresh');
    expect(body['device'], {'id': 'device-1'});
  });

  test('catalog is TTL-cached; orders are never cached', () async {
    var catalogCalls = 0;
    var orderCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/catalog')) {
        catalogCalls += 1;
        return _json({'skus': []});
      }
      orderCalls += 1;
      return _json({'data': [], 'next_cursor': null});
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.example.test/v1',
      accessToken: 'token-a',
    );

    await api.catalog();
    await api.catalog();
    await api.listOrders();
    await api.listOrders();

    expect(catalogCalls, 1);
    expect(orderCalls, 2);
  });

  test('windows cache key includes date and pincode', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      return _json({'windows': []});
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.example.test/v1',
    );

    await api.windows(date: '2026-10-24', pincode: '462001');
    await api.windows(date: '2026-10-24', pincode: '462001');
    await api.windows(date: '2026-10-24', pincode: '462002');

    expect(calls, 2);
  });

  test('logout revokes with the captured token after local clear', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return _json({'ok': true});
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.example.test/v1',
      deviceId: 'device-1',
    );

    await ApiBackedAuthApi(api).logout('captured-access');

    expect(seen.url.path, '/v1/auth/logout');
    expect(seen.headers['authorization'], 'Bearer captured-access');
  });
}
