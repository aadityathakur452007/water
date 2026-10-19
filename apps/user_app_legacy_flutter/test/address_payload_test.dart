// Address wire contract (§4.3 + 011_port): the typed line rides on
// `formatted` (server has no address_line column); house/street/area/phone
// ride as their own columns. Guards the "can't change address" regression
// where saves came back with empty text.

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
      'house': body['house'],
      'street': body['street'],
      'area': body['area'],
      'phone': body['phone'],
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

    // 011_port: full-format fields ride along and round-trip.
    const full = AddressEntry(
      id: '',
      label: 'Ghar',
      type: AddrType.home,
      phone: '9876543210',
      pincode: '560002',
      addressLine: '12 Main Rd',
      lat: 12.9,
      lng: 77.5,
      house: '12',
      street: 'Main Rd',
      area: 'Indiranagar',
    );
    expect(await c.save(full, isNew: true), isTrue);
    expect(posted!['house'], '12');
    expect(posted!['area'], 'Indiranagar');
    expect(posted!['phone'], '9876543210');
    expect(c.items.last.house, '12');
    expect(c.resolve()?.id, 'a1'); // last saved becomes the selection
    c.select('nope-missing');
    expect(c.resolve()?.id, 'a1'); // unknown id falls back, never null-crash

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
