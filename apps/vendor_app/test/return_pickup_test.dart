// F8 pickup: return stop shows pickup card (not triple/PoD/cash) + posts.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/core/theme.dart';
import 'package:vendor_app/features/stops/stop_detail_screen.dart';
import 'package:vendor_app/features/stops/stops_controller.dart';

void main() {
  testWidgets('pickup card posts collected counts', (tester) async {
    var pickupCalls = 0;
    final mock = MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/vendor/stops/sp1') && req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'id': 'sp1',
            'route_id': 'r1',
            'order_id': null,
            'return_id': 'ret1',
            'customer_id': 'u1',
            'seq': 9,
            'fulls_exp': 0,
            'empties_exp': 2,
            'version': 1,
            'status': 'pending',
            'customer_name': 'Sharma Ji',
          }),
          200,
        );
      }
      if (p.endsWith('/returns/ret1/pickup')) {
        pickupCalls++;
        final body = jsonDecode(req.body);
        expect(body['empties_collected'], 2);
        return http.Response(
          jsonEncode({'id': 'ret1', 'status': 'picked', 'cap_charge': 0}),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final api = ApiClient(client: mock, deviceId: 'test-device');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: StopDetailScreen(
          controller: StopsController(api: api),
          stopId: 'sp1',
          stopLabel: 'Pickup',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    // Pickup card only — no triple/PoD/cash actions.
    expect(find.textContaining('Khaali pickup'), findsWidgets);
    expect(find.textContaining('Triple'), findsNothing);
    expect(find.textContaining('PoD'), findsNothing);
    expect(find.textContaining('Cash jama'), findsNothing);

    await tester.tap(find.text('Pickup complete karein'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(pickupCalls, 1);
    expect(find.text('Khaali jama ho gaye'), findsOneWidget);
  });
}
