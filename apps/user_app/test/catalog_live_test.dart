// Phase 4 §4.4 — live catalog: server rates populate, admin rate change
// flows through, failures keep the hardcoded fallback. MockClient, no backend.

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

void main() {
  group('HttpCatalogApi', () {
    test('server payload populates rates', () async {
      final api = catalogApi({
        'skus': [
          {'id': 'refill', 'price_paise': 2800},
          {'id': 'container', 'price_paise': 3000},
        ],
        'deposit_per_jar': 15000,
        'cap_charge': 300,
        'hours': '08:00-20:00, all days',
        'holidays': [],
      });
      final rates = await HttpCatalogApi(api).fetchRates();
      expect(rates.refillPaise, 2800);
      expect(rates.containerPaise, 3000);
      expect(rates.depositPaise, 15000);
      expect(rates.capPaise, 300);
    });

    test('admin rate change reaches the client (no app update)', () async {
      final api = catalogApi({
        'skus': [
          {'id': 'refill', 'price_paise': 3200},
          {'id': 'container', 'price_paise': 3500},
        ],
        'deposit_per_jar': 15000,
        'cap_charge': 500,
        'hours': '',
        'holidays': [],
      });
      final rates = await HttpCatalogApi(api).fetchRates();
      expect(rates.refillPaise, 3200);
      expect(rates.containerPaise, 3500);
      expect(rates.capPaise, 500);
    });

    test('missing fields fall back per-field (never throws to UI)', () async {
      final api = catalogApi({'skus': [], 'hours': '', 'holidays': []});
      final rates = await HttpCatalogApi(api).fetchRates();
      expect(rates.refillPaise, kRateRefillPaise);
      expect(rates.containerPaise, kRateContainerPaise);
      expect(rates.depositPaise, kDepositPerJarPaise);
      expect(rates.capPaise, kCapChargePaise);
    });
  });

  group('CachingCatalogApi offline honesty', () {
    test('failure keeps last cached rates (never throws to UI)', () async {
      final inner = _FlipCatalog(const CatalogRates(refillPaise: 2900));
      final caching = CachingCatalogApi(inner);
      final first = await caching.fetchRates();
      expect(first.refillPaise, 2900);
      // Network drops: same call now serves the cached snapshot.
      inner.rates = null;
      final second = await caching.fetchRates();
      expect(second.refillPaise, 2900);
    });

    test('BookingController.refreshRates applies live rates', () async {
      final api = catalogApi({
        'skus': [
          {'id': 'refill', 'price_paise': 3300},
          {'id': 'container', 'price_paise': 3600},
        ],
        'deposit_per_jar': 15000,
        'cap_charge': 300,
        'hours': '',
        'holidays': [],
      });
      final c = BookingController(
        catalog: CachingCatalogApi(HttpCatalogApi(api)),
      );
      await c.refreshRates();
      expect(c.rates.refillPaise, 3300);
      expect(c.rates.containerPaise, 3600);
      c.dispose();
    });
  });
}

/// Controllable inner source: serves [rates], or throws NETWORK when null.
class _FlipCatalog implements CatalogApi {
  _FlipCatalog(this.rates);

  CatalogRates? rates;

  @override
  Future<CatalogRates> fetchRates() async {
    final r = rates;
    if (r == null) {
      throw ApiException(
        code: 'NETWORK',
        message: 'Network unavailable',
        statusCode: 0,
      );
    }
    return r;
  }
}
