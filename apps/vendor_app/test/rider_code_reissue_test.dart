// The rider list's key action rotates a rider's sign-in code
// (POST /vendor/riders/{id}/code). Success must show the once-only code dialog;
// failure must surface the server's message in a snackbar. MockClient, no
// backend.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/core/theme.dart';
import 'package:vendor_app/core/vendor_locale.dart';
import 'package:vendor_app/features/riders/riders_screen.dart';

const _rider = {
  'id': 'r1',
  'name': 'Ravi Kumar',
  'phone': '+919876543210',
  'suspended': 0,
};

const _rotatedCode = '445566';

/// Serves the rider list and answers the rotate call with [onCode].
/// [posts] counts rotate calls so the test can prove the tap hit the endpoint.
MockClient _mock(
  http.Response Function() onCode, {
  List<String>? posts,
}) =>
    MockClient((req) async {
      if (req.method == 'GET' && req.url.path.endsWith('/vendor/riders')) {
        return http.Response(jsonEncode({'data': [_rider]}), 200);
      }
      if (req.method == 'POST' &&
          req.url.path.endsWith('/vendor/riders/r1/code')) {
        posts?.add(req.url.path);
        return onCode();
      }
      return http.Response(
        jsonEncode({
          'error': {'code': 'NOT_FOUND', 'message': 'Unexpected request'}
        }),
        404,
      );
    });

ApiClient _api(MockClient mock) =>
    ApiClient(client: mock, deviceId: 'test-device', accessToken: 'token');

Future<void> _pumpRiders(WidgetTester tester, ApiClient api) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildShodashaTheme(),
      home: RidersScreen(api: api),
    ),
  );
  await tester.pump(); // initState -> listRiders()
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _codeText(String code) => find.byWidgetPredicate(
      (w) => w is SelectableText && w.data == code,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The dialog's button label and the row tooltip are locale-driven.
  setUp(() => VendorLocaleController.instance.resetForTest('en'));

  testWidgets('key icon rotates the code and shows it once in a dialog',
      (tester) async {
    final posts = <String>[];
    final api = _api(_mock(
      () => http.Response(
        jsonEncode({
          'id': 'r1',
          'access_code': _rotatedCode,
          'access_code_expires_at': '2027-02-01T00:00:00+00:00',
        }),
        200,
      ),
      posts: posts,
    ));

    await _pumpRiders(tester, api);
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.byIcon(Icons.key_rounded), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.byIcon(Icons.key_rounded));
    await tester.pumpAndSettle();

    expect(posts, ['/v1/vendor/riders/r1/code']);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_codeText(_rotatedCode), findsOneWidget);

    // The dialog is dismissible and the list is still there afterwards.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Ravi Kumar'), findsOneWidget);
  });

  testWidgets('failed re-issue shows the server message and no dialog',
      (tester) async {
    final posts = <String>[];
    final api = _api(_mock(
      () => http.Response(
        jsonEncode({
          'error': {
            'code': 'STATE_CONFLICT',
            'message': 'This rider belongs to another vendor.',
          }
        }),
        409,
      ),
      posts: posts,
    ));

    await _pumpRiders(tester, api);
    await tester.tap(find.byIcon(Icons.key_rounded));
    await tester.pump(); // fire the request
    await tester.pump(const Duration(milliseconds: 50)); // snackbar entrance

    expect(posts, ['/v1/vendor/riders/r1/code']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('This rider belongs to another vendor.'), findsOneWidget);
  });
}
