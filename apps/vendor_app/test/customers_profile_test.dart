// Customers + support-queue + profile client tests (011_port).
// MockClient, no backend.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/features/customers/customers_controller.dart';
import 'package:vendor_app/features/support/support_controller.dart';

MockClient _mock() => MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/vendor/customers')) {
        return http.Response(
            jsonEncode({
              'date': '2026-10-02',
              'customers': [
                {
                  'customer_id': 'u1',
                  'customer_name': 'Cust One',
                  'customer_phone': '+912222222222',
                  'stops': [
                    {'stop_id': 's1', 'seq': 0, 'status': 'done', 'order_id': 'o1'},
                    {'stop_id': 's2', 'seq': 1, 'status': 'pending', 'order_id': 'o2'},
                  ],
                  'fulls_exp': 3,
                  'empties_exp': 1,
                  'done': 1,
                }
              ]
            }),
            200);
      }
      if (p.endsWith('/vendor/complaints')) {
        return http.Response(
            jsonEncode({
              'data': [
                {'id': 'c1', 'order_id': 'o1', 'reason_code': 'short_delivery', 'text': 'one short', 'status': 'open'}
              ]
            }),
            200);
      }
      if (p.endsWith('/vendor/profile') && req.method == 'PATCH') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({'user_id': 'v1', 'name': body['name'], 'phone': '', 'address': '', 'hours': ''}), 200);
      }
      if (p.endsWith('/vendor/profile')) {
        return http.Response(
            jsonEncode({'user_id': 'v1', 'name': 'Ramu', 'phone': '', 'address': '', 'hours': '8-8'}), 200);
      }
      return http.Response('not found', 404);
    });

void main() {
  test('customers load groups + search filters', () async {
    final c = CustomersController(
        api: ApiClient(client: _mock(), deviceId: 't'));
    await c.load();
    expect(c.state, CustomersState.loaded);
    expect(c.items.single.name, 'Cust One');
    expect(c.items.single.pending, 1);
    c.setQuery('no-match-xyz');
    expect(c.items, isEmpty);
    c.setQuery('cust');
    expect(c.items.single.id, 'u1');
    c.dispose();
  });

  test('support queue loads, profile round-trips', () async {
    final api = ApiClient(client: _mock(), deviceId: 't');
    final s = SupportController(api: api);
    await s.loadQueue();
    expect(s.queue.single['id'], 'c1');
    final profile = await api.vendorProfile();
    expect(profile['name'], 'Ramu');
    final saved = await api.saveVendorProfile({'name': 'Ramu Jr'});
    expect(saved['name'], 'Ramu Jr');
    s.dispose();
  });
}
