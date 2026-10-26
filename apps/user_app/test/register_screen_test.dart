// S2 register-screen spec: CTA gate (valid name + @gmail.com + 10-digit
// phone), non-user/staff-number honest errors, loading lock, and the
// server-gated demo door never faking success. Plugin-free: in-memory
// session store, fake AuthApi, no HTTP / secure storage.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/auth/auth_controller.dart';
import 'package:shodasha_app/features/auth/demo_sheet.dart';
import 'package:shodasha_app/features/auth/name_number_screen.dart';

class _FakeApi implements AuthApi {
  _FakeApi({
    this.role = 'user',
    this.registerError,
    this.demoError,
    this.registerWaiter,
  });

  final String role;
  final ApiException? registerError;
  final ApiException? demoError;
  final Completer<void>? registerWaiter;
  int registerCalls = 0;

  AuthSession _session() => AuthSession(
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(days: 30)),
    role: role,
    verified: false,
  );

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String deviceId,
  }) async {
    registerCalls += 1;
    if (registerWaiter != null) await registerWaiter!.future;
    if (registerError != null) throw registerError!;
    return _session();
  }

  @override
  Future<AuthSession> demoLogin({
    required String phone,
    required String code,
    required String deviceId,
  }) async {
    if (demoError != null) throw demoError!;
    return _session();
  }

  @override
  Future<void> logout(String accessToken) async {}
}

Future<AuthController> _pumpScreen(
  WidgetTester tester,
  _FakeApi api, {
  VoidCallback? onGuestBrowse,
  VoidCallback? onRegistered,
}) async {
  final controller = AuthController(
    api: api,
    store: InMemorySessionStore(),
    deviceId: 'test-device',
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildShodashaTheme(),
      home: NameNumberScreen(
        controller: controller,
        onGuestBrowse: onGuestBrowse,
        onRegistered: onRegistered,
      ),
    ),
  );
  await tester.pump();
  return controller;
}

Finder _field(int index) => find.byType(TextField).at(index);

Future<void> _fillValid(
  WidgetTester tester, {
  String name = 'Naya User',
  String email = 'naya@gmail.com',
  String phone = '9876543210',
}) async {
  await tester.enterText(_field(0), name);
  await tester.enterText(_field(1), email);
  await tester.enterText(_field(2), phone);
  await tester.pump();
}

bool _ctaEnabled(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed !=
    null;

Future<void> _tapCta(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Create Account'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Create Account'));
}

void main() {
  testWidgets('CTA stays disabled until name + gmail + 10-digit phone valid', (
    tester,
  ) async {
    await _pumpScreen(tester, _FakeApi());
    expect(_ctaEnabled(tester), isFalse);

    await tester.enterText(_field(0), 'Naya User');
    await tester.pump();
    expect(_ctaEnabled(tester), isFalse, reason: 'email + phone missing');

    await tester.enterText(_field(1), 'naya@gmail.com');
    await tester.pump();
    expect(_ctaEnabled(tester), isFalse, reason: 'phone missing');

    await tester.enterText(_field(2), '987654321'); // 9 digits
    await tester.pump();
    expect(_ctaEnabled(tester), isFalse, reason: 'phone too short');

    await tester.enterText(_field(2), '9876543210');
    await tester.pump();
    expect(_ctaEnabled(tester), isTrue);
  });

  testWidgets('email is gmail-only (non-gmail keeps the CTA disabled)', (
    tester,
  ) async {
    await _pumpScreen(tester, _FakeApi());
    await _fillValid(tester, email: 'naya@yahoo.com');
    expect(_ctaEnabled(tester), isFalse);

    await tester.enterText(_field(1), 'naya@gmail.com');
    await tester.pump();
    expect(_ctaEnabled(tester), isTrue);
  });

  testWidgets('phone is capped at 10 digits', (tester) async {
    await _pumpScreen(tester, _FakeApi());
    await tester.enterText(_field(2), '98765432101'); // formatter truncates
    await tester.pump();
    expect(tester.widget<TextField>(_field(2)).controller?.text, '9876543210');
  });

  testWidgets('non-user register is rejected with the honest role copy', (
    tester,
  ) async {
    final controller = await _pumpScreen(tester, _FakeApi(role: 'vendor'));
    await _fillValid(tester);
    await _tapCta(tester);
    await tester.pumpAndSettle();

    expect(controller.isAuthenticated, isFalse);
    expect(find.text(authStringsHi['notUser']!), findsOneWidget);
  });

  testWidgets('422 ROLE_RESERVED maps to the staff-number copy', (
    tester,
  ) async {
    final api = _FakeApi(
      registerError: ApiException(
        code: 'ROLE_RESERVED',
        message: 'ROLE_RESERVED',
        statusCode: 422,
      ),
    );
    final controller = await _pumpScreen(tester, api);
    await _fillValid(tester);
    await _tapCta(tester);
    await tester.pumpAndSettle();

    expect(controller.isAuthenticated, isFalse);
    expect(find.text(authStringsHi['staffNumber']!), findsOneWidget);
  });

  testWidgets('submitting disables the CTA and shows in-flight feedback', (
    tester,
  ) async {
    final waiter = Completer<void>();
    final api = _FakeApi(registerWaiter: waiter);
    final controller = await _pumpScreen(tester, api);
    await _fillValid(tester);
    await _tapCta(tester);
    await tester.pump();

    expect(controller.status, AuthStatus.verifying);
    expect(_ctaEnabled(tester), isFalse);
    expect(find.text('Creating your account…'), findsOneWidget);

    waiter.complete();
    await tester.pumpAndSettle();
    expect(controller.isAuthenticated, isTrue);
    expect(api.registerCalls, 1);
  });

  testWidgets('demo failure surfaces the server error, never fake success', (
    tester,
  ) async {
    final api = _FakeApi(
      demoError: ApiException(
        code: 'UNAUTH',
        message: 'Demo door is closed',
        statusCode: 401,
      ),
    );
    final controller = await _pumpScreen(tester, api);

    await tester.ensureVisible(find.text('Try the demo account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try the demo account'));
    await tester.pumpAndSettle();
    expect(find.text('Demo login'), findsOneWidget);

    await tester.tap(find.text('Fill demo customer'));
    await tester.pump();
    await tester.ensureVisible(find.text('Login with demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login with demo'));
    await tester.pumpAndSettle();

    expect(controller.isAuthenticated, isFalse);
    // Scoped to the sheet: the register screen behind it also renders the
    // same controller error (honest, and visible if the sheet is dismissed).
    expect(
      find.descendant(
        of: find.byType(UserDemoSheet),
        matching: find.text('Demo door is closed'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('guest browse is offered and reports the tap', (tester) async {
    var guest = 0;
    await _pumpScreen(tester, _FakeApi(), onGuestBrowse: () => guest += 1);

    await tester.ensureVisible(find.text('Browse without an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse without an account'));
    expect(guest, 1);
  });
}
