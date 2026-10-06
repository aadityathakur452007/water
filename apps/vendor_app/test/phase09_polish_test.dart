// Phase 9 re-verify (ADR-091): vendor stop pending→done renders the
// done check instantly on reload — deliberately static (every reload
// passes through the loading skeleton, which unmounts the row, so a flip
// transition could never play; avatar + row flip + jama notice carry it).
// Run: flutter test test/phase09_polish_test.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/core/theme.dart';
import 'package:vendor_app/features/route/route_controller.dart';
import 'package:vendor_app/features/route/route_screen.dart';

Map<String, dynamic> _stop(String status) => {
      'id': 's1',
      'seq': 1,
      'customer_name': 'Sharma',
      'address_text': 'Sector 21',
      'fulls_exp': 2,
      'empties_exp': 1,
      'total': 5600,
      'version': 1,
      'status': status,
      'payment_mode': 'cod',
      'payment_status': 'unpaid',
    };

MockClient _mock(String Function() status) => MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/vendor/routes/today')) {
        return http.Response(
            jsonEncode({
              'route': {'id': 'r1'},
              'stops': [_stop(status())],
              'skip': [],
              'loading': {'take_fulls': 0, 'expect_empties': 0},
            }),
            200);
      }
      if (p.endsWith('/vendor/profile')) {
        return http.Response(
            jsonEncode({'user_id': 'v1', 'on_duty': true}), 200);
      }
      return http.Response('not found', 404);
    });

Widget _screen(RouteController c) => MaterialApp(
      theme: buildShodashaTheme(),
      home: RouteScreen(controller: c, onOpenStop: (_) {}),
    );

void main() {
  group('Phase 9 re-verify §9.1 stop pending→done (static by design)', () {
    testWidgets('done check appears on reload with no mid-flight fade',
        (tester) async {
      var status = 'pending';
      final c = RouteController(
          api: ApiClient(client: _mock(() => status), deviceId: 't'));
      await tester.pumpWidget(_screen(c));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      // Scroll the row into view first: lazy lists skip offstage children.
      await tester.scrollUntilVisible(find.text('Sharma'), 200);
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsNothing);

      status = 'done';
      await c.load();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      // No transition ever plays: every settled fade sits at exactly 1.
      final fades =
          tester.widgetList<FadeTransition>(find.byType(FadeTransition));
      expect(fades.every((w) => w.opacity.value == 1.0), isTrue);
    });
  });
}
