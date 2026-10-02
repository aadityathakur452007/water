// Address wire contract (§4.3): the typed line rides on `formatted`
// (server has no address_line/phone columns). Guards the "can't change
// address" regression where saves came back with empty text.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/features/addresses/address_screen.dart';

Map<String, dynamic> _row(Map<String, dynamic> body, String id) => {
      'id': id,
      'type': body['type'],
      'label': body['label'],
      'lat': body['lat'],
      'lng': body['lng'],
      'place_id': null,
      'formatted': body['formatted'],
      'landmark': body['landmark'],
      'pincode': body['pincode'],
      'lift_flag': body['lift_flag'],
    };

void main() {
  test('save() sends formatted (not address_line) and round-trips text',
      () async {
    Map<String, dynamic>? posted;
    final mock = MockClient((req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/addresses')) {
        posted = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_row(posted!, 'a1')), 201);
      }
      if (req.method == 'PATCH') {
        posted = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_row(posted!, 'a1')), 200);
      }
      if (req.method == 'GET') {
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response('not found', 404);
    });
    final c = AddressController(api: ApiClient(client: mock, deviceId: 't'));
    const entry = AddressEntry(
      id: '',
      label: 'Ghar',
      type: AddrType.home,
      phone: '9302190067',
      pincode: '110001',
      addressLine: 'House 12, MG Road',
      lift: true,
      lat: 28.6,
      lng: 77.2,
    );
    expect(await c.save(entry, isNew: true), isTrue);
    expect(posted!['formatted'], 'House 12, MG Road');
    expect(posted!.containsKey('address_line'), isFalse);
    expect(c.items.single.addressLine, 'House 12, MG Road');

    expect(
        await c.save(
          const AddressEntry(
            id: 'a1',
            label: 'Ghar',
            type: AddrType.home,
            phone: '',
            pincode: '110001',
            addressLine: 'House 14, MG Road',
            lat: 28.6,
            lng: 77.2,
          ),
          isNew: false,
        ),
        isTrue);
    expect(posted!['formatted'], 'House 14, MG Road');
    expect(c.items.single.addressLine, 'House 14, MG Road');
    c.dispose();
  });
}
