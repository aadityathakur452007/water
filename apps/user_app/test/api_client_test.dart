// Regression for ADR-051: typed ApiClient methods must await [send] then
// cast the value — `send(...) as Future<Map>` throws at runtime.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';

void main() {
  test('catalog() resolves a typed map (no Future-cast error)', () async {
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/catalog')) {
        return http.Response(
          jsonEncode({
            'skus': [
              {'id': 'refill', 'price_paise': 2800},
              {'id': 'container', 'price_paise': 3000},
            ],
            'deposit_per_jar': 15000,
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final api = ApiClient(client: mock, deviceId: 'test-device');
    final out = await api.catalog();
    expect(out['deposit_per_jar'], 15000);
    expect((out['skus'] as List).length, 2);
  });

  test('offline follows transport, not HTTP status', () async {
    var down = true;
    final mock = MockClient((req) async {
      if (down) throw http.ClientException('no route');
      return http.Response('{"ok":true}', 200);
    });
    final api = ApiClient(client: mock, deviceId: 'test-device');
    expect(api.offline.value, isFalse);

    await expectLater(api.catalog(), throwsA(isA<ApiException>()));
    expect(api.offline.value, isTrue);

    down = false;
    await api.catalog();
    expect(api.offline.value, isFalse);

    // A 500 still means the socket works — never a false "offline".
    final failing = ApiClient(
      client: MockClient((req) async => http.Response('oops', 500)),
      deviceId: 'test-device',
    );
    await expectLater(failing.catalog(), throwsA(isA<ApiException>()));
    expect(failing.offline.value, isFalse);
  });
}
