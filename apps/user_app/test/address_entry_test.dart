// Address entry regression tests.
// F1: the shared client sends the live Bearer.
// F2: the entry gate never strands guests on a 401.
// F4: load() re-adopts a persisted selection that arrived before the items.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/features/addresses/address_screen.dart';
import 'package:shodasha_app/features/addresses/selected_address_store.dart';

Map<String, dynamic> _row(String id, String label) => {
      'id': id,
      'label': label,
      'type': 'home',
      'phone': '9302190067',
      'pincode': '110001',
      'formatted': 'House 12, MG Road',
      'lat': 28.6,
      'lng': 77.2,
    };

void main() {
  test('F1: authed calls carry the live Bearer from the getter', () async {
    String? seen;
    String? token = 'tok-1';
    final api = ApiClient(
      client: MockClient((req) async {
        seen = req.headers['Authorization'];
        if (req.url.path.endsWith('/addresses')) {
          return http.Response(jsonEncode([_row('a1', 'Home')]), 200);
        }
        return http.Response('not found', 404);
      }),
      deviceId: 't',
      accessTokenGetter: () => token,
    );

    await api.listAddresses();
    expect(seen, 'Bearer tok-1');

    // Live switch without rebuilding the client (post-login/restore path).
    token = 'tok-2';
    await api.listAddresses();
    expect(seen, 'Bearer tok-2');

    // Logged out: no header (server 401s honestly instead of a stale token).
    token = null;
    await api.listAddresses();
    expect(seen == null || !seen!.startsWith('Bearer '), isTrue);
  });

  testWidgets('F2: guest goes login-first, then addresses on success',
      (tester) async {
    var logins = 0;
    var addressesOpened = 0;
    var authed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => openAddressesGated(
              ctx,
              isAuthed: () => authed,
              ensureAuth: (_) async {
                logins++;
                authed = true; // fake OTP success
                return true;
              },
              openAddresses: (_) => addressesOpened++,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(logins, 1);
    expect(addressesOpened, 1);
  });

  testWidgets('F2: guest who cancels login never reaches addresses',
      (tester) async {
    var logins = 0;
    var addressesOpened = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => openAddressesGated(
              ctx,
              isAuthed: () => false,
              ensureAuth: (_) async {
                logins++;
                return false; // user backs out: still a guest
              },
              openAddresses: (_) => addressesOpened++,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(logins, 1);
    expect(addressesOpened, 0);
  });

  testWidgets('F2: authed user skips login entirely', (tester) async {
    var logins = 0;
    var addressesOpened = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => openAddressesGated(
              ctx,
              isAuthed: () => true,
              ensureAuth: (_) async {
                logins++;
                return false;
              },
              openAddresses: (_) => addressesOpened++,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(logins, 0);
    expect(addressesOpened, 1);
  });

  test('F4: load() re-adopts a persisted selection (restart race)', () async {
    SharedPreferences.setMockInitialValues({SelectedAddressStore.key: 'a2'});
    final store = SelectedAddressStore();
    await store.load();
    expect(store.selectedId, 'a2');

    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/addresses')) {
        return http.Response(
            jsonEncode([_row('a1', 'Home'), _row('a2', 'Office')]), 200);
      }
      return http.Response('not found', 404);
    });
    final c = AddressController(api: ApiClient(client: mock, deviceId: 't'));
    // bindSelection runs before first load in main — items are empty then,
    // so nothing is adopted yet (the race).
    c.bindSelection(store);
    expect(c.selectedId, isNull);

    await c.load();

    // After load the persisted choice is adopted and resolves.
    expect(c.selectedId, 'a2');
    expect(c.resolve()?.id, 'a2');
    c.dispose();
  });
}
