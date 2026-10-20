// S8 profile spec: guest gate, invalid phone/@gmail.com blocks PATCH, valid
// save sends the trimmed contract body, server messages pass through, logout
// is confirmed (destructive, never a green CTA), and optional destination
// rows only appear when their callback exists. Plugin-free (mocked http).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/profile/profile_controller.dart';
import 'package:shodasha_app/features/profile/profile_screen.dart';

const _user = {
  'id': 'u1',
  'name': 'Asha Rao',
  'phone': '9876543210',
  'email': 'asha@gmail.com',
};

ApiClient _api(MockClient client) => ApiClient(
  client: client,
  accessToken: 'tok',
  deviceId: 'dev',
  baseUrl: 'http://localhost:8787/v1',
);

/// Opens Profile with a large surface so every row is built (no flaky
/// off-screen finders) and the identity request settles.
Future<void> _pumpProfile(WidgetTester tester, Widget home) async {
  await tester.binding.setSurfaceSize(const Size(500, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(theme: buildShodashaTheme(), home: home));
  await tester.pumpAndSettle();
}

ProfileScreen _screen(
  ApiClient api, {
  ProfileController? controller,
  VoidCallback? onLoginRequired,
  Future<void> Function()? onLogout,
  VoidCallback? onOpenAddresses,
  VoidCallback? onOpenPayments,
  VoidCallback? onOpenReturns,
  bool isAuthenticated = true,
}) => ProfileScreen(
  api: api,
  isAuthenticated: isAuthenticated,
  controller: controller,
  onLoginRequired: onLoginRequired,
  onLogout: onLogout,
  onOpenAddresses: onOpenAddresses,
  onOpenPayments: onOpenPayments,
  onOpenReturns: onOpenReturns,
);

void main() {
  testWidgets('guest sees the log-in CTA and fires zero requests', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final api = _api(
      MockClient((req) async {
        requests.add(req);
        return http.Response('{}', 200);
      }),
    );
    var loginTaps = 0;

    await _pumpProfile(
      tester,
      _screen(
        api,
        isAuthenticated: false,
        onLoginRequired: () => loginTaps += 1,
      ),
    );

    expect(find.text('Log in to view your account'), findsOneWidget);
    await tester.tap(find.text('Log in'));
    expect(loginTaps, 1);
    expect(requests, isEmpty);
  });

  testWidgets('invalid phone + non-gmail email block the PATCH', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final api = _api(
      MockClient((req) async {
        requests.add(req);
        if (req.method == 'PATCH') return http.Response('{}', 200);
        return http.Response(jsonEncode({'user': _user}), 200);
      }),
    );

    await _pumpProfile(tester, _screen(api));

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-phone')), '12345');
    await tester.enterText(
      find.byKey(const Key('profile-email')),
      'asha@yahoo.com',
    );
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(find.text(kProfilePhoneError), findsOneWidget);
    expect(find.text(kProfileEmailError), findsOneWidget);
    expect(requests.where((r) => r.method == 'PATCH'), isEmpty);
  });

  testWidgets('valid save PATCHes the trimmed body and refreshes identity', (
    tester,
  ) async {
    final patches = <http.Request>[];
    final api = _api(
      MockClient((req) async {
        if (req.method == 'PATCH') {
          patches.add(req);
          return http.Response(
            jsonEncode({
              'user': {
                ..._user,
                'name': 'Asha Rao',
                'phone': '9876543210',
                'email': 'asha@gmail.com',
              },
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'user': _user}), 200);
      }),
    );

    await _pumpProfile(tester, _screen(api));

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-name')),
      '  Asha Rao  ',
    );
    await tester.enterText(
      find.byKey(const Key('profile-phone')),
      '9876543210',
    );
    await tester.enterText(
      find.byKey(const Key('profile-email')),
      'asha@gmail.com',
    );
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(patches, hasLength(1));
    final patch = patches.single;
    expect(patch.url.path, endsWith('/auth/me'));
    expect(
      patch.headers['Authorization'] ?? patch.headers['authorization'],
      'Bearer tok',
    );
    expect(patch.headers['X-Device-Id'] ?? patch.headers['x-device-id'], 'dev');
    expect(jsonDecode(patch.body), {
      'name': 'Asha Rao',
      'phone': '9876543210',
      'email': 'asha@gmail.com',
    });
    expect(find.text('Profile updated.'), findsOneWidget);
    expect(find.text('Asha Rao'), findsOneWidget);
  });

  testWidgets('server validation message passes through verbatim', (
    tester,
  ) async {
    final api = _api(
      MockClient((req) async {
        if (req.method == 'PATCH') {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'VALIDATION',
                'message': 'This mobile number is already registered.',
              },
            }),
            400,
          );
        }
        return http.Response(jsonEncode({'user': _user}), 200);
      }),
    );

    await _pumpProfile(tester, _screen(api));

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-phone')),
      '9000000001',
    );
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(
      find.text('This mobile number is already registered.'),
      findsOneWidget,
    );
    // The sheet stays open so the user can correct the value.
    expect(find.byKey(const Key('profile-save')), findsOneWidget);
  });

  testWidgets('logout asks first and only then calls onLogout', (tester) async {
    final api = _api(
      MockClient(
        (req) async => http.Response(jsonEncode({'user': _user}), 200),
      ),
    );
    var logouts = 0;

    await _pumpProfile(
      tester,
      _screen(api, onLogout: () async => logouts += 1),
    );

    final logoutTile = find.text('Log out');
    expect(tester.widget<Text>(logoutTile).style?.color, ShodashaTheme.danger);

    await tester.tap(logoutTile);
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(logouts, 0);

    await tester.tap(logoutTile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, log out'));
    await tester.pumpAndSettle();
    expect(logouts, 1);
  });

  testWidgets('account rows fire their callbacks when provided', (
    tester,
  ) async {
    final api = _api(
      MockClient(
        (req) async => http.Response(jsonEncode({'user': _user}), 200),
      ),
    );
    var addresses = 0;
    var payments = 0;
    var returns = 0;

    await _pumpProfile(
      tester,
      _screen(
        api,
        onOpenAddresses: () => addresses += 1,
        onOpenPayments: () => payments += 1,
        onOpenReturns: () => returns += 1,
      ),
    );

    await tester.tap(find.text('Saved addresses'));
    await tester.tap(find.text('Payments & deposits'));
    await tester.tap(find.text('Return jars'));
    await tester.pump();

    expect(addresses, 1);
    expect(payments, 1);
    expect(returns, 1);
  });

  testWidgets('account rows are hidden when their destination is absent', (
    tester,
  ) async {
    final api = _api(
      MockClient(
        (req) async => http.Response(jsonEncode({'user': _user}), 200),
      ),
    );

    await _pumpProfile(tester, _screen(api));

    expect(find.text('Saved addresses'), findsNothing);
    expect(find.text('Payments & deposits'), findsNothing);
    expect(find.text('Return jars'), findsNothing);
    expect(find.text('Help & support'), findsOneWidget);
  });
}
