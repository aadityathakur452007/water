// Live catalog: server rates populate, admin changes flow through, and
// failures stay honest — no hardcoded fallback, no cache. MockClient only.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/features/booking/booking_controller.dart';

ApiClient catalogApi(Map<String, dynamic> payload) {
  final mock = MockClient((req) async {
    if (req.url.path.endsWith('/catalog')) {
      return http.Response(jsonEncode(payload), 200);
    }
    return http.Response('not found', 404);
  });
  return ApiClient(client: mock, deviceId: 't');
}

Map<String, dynamic> _payload({
  int refill = 2800,
  int container = 3000,
  int deposit = 15000,
  int cap = 300,
}) =>
    {
      'skus': [
        {'id': 'refill', 'price_paise': refill},
        {'id': 'container', 'price_paise': container},
      ],
      'deposit_per_jar': deposit,
      'cap_charge': cap,
      'hours': '08:00-20:00, all days',
      'holidays': [],
    };

void main() {
  group('HttpCatalogApi', () {
    test('server payload populates rates', () async {
      final rates = await HttpCatalogApi(catalogApi(_payload())).fetchRates();
      expect(rates.refillPaise, 2800);
      expect(rates.containerPaise, 3000);
      expect(rates.depositPaise, 15000);
      expect(rates.capPaise, 300);
    });

    test('admin rate change reaches the client (no app update)', () async {
      final rates = await HttpCatalogApi(
        catalogApi(_payload(refill: 3200, container: 3500, cap: 500)),
      ).fetchRates();
      expect(rates.refillPaise, 3200);
      expect(rates.containerPaise, 3500);
      expect(rates.capPaise, 500);
    });

    test('missing price fields throw CatalogUnavailable (no fallback)',
        () async {
      final api = catalogApi({'skus': [], 'hours': '', 'holidays': []});
      await expectLater(
        HttpCatalogApi(api).fetchRates(),
        throwsA(isA<CatalogUnavailable>()),
      );
    });

    test('missing deposit throws CatalogUnavailable', () async {
      final payload = _payload()..remove('deposit_per_jar');
      await expectLater(
        HttpCatalogApi(catalogApi(payload)).fetchRates(),
        throwsA(isA<CatalogUnavailable>()),
      );
    });

    test('network failure throws ApiException (never cached rates)',
        () async {
      final mock = MockClient((_) async => http.Response('down', 400));
      final api = ApiClient(client: mock, deviceId: 't');
      await expectLater(
        HttpCatalogApi(api).fetchRates(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('BookingController.refreshRates', () {
    test('applies live rates from the server', () async {
      final c = BookingController(
        catalog: HttpCatalogApi(
          catalogApi(_payload(refill: 3300, container: 3600)),
        ),
      );
      await c.refreshRates();
      expect(c.rates, isNotNull);
      expect(c.rates!.refillPaise, 3300);
      expect(c.rates!.containerPaise, 3600);
      expect(c.ratesError, isNull);
      c.dispose();
    });

    test('network failure stays honest: error surfaced, rates null',
        () async {
      final c = BookingController(catalog: _FailingCatalog());
      await c.refreshRates();
      expect(c.rates, isNull);
      expect(c.ratesError, contains('No internet'));
      c.dispose();
    });

    test('incomplete payload surfaces the catalog message', () async {
      final c = BookingController(
        catalog: HttpCatalogApi(catalogApi({'skus': []})),
      );
      await c.refreshRates();
      expect(c.rates, isNull);
      expect(c.ratesError, isNotEmpty);
      c.dispose();
    });
  });
}

/// Controllable inner source that always reports a network failure.
class _FailingCatalog implements CatalogApi {
  @override
  Future<CatalogRates> fetchRates() async {
    throw ApiException(
      code: 'NETWORK',
      message: 'Network unavailable',
      statusCode: 0,
    );
  }
}
