// S2 auth-gate spec: in-flight restore splash, authenticated → home,
// guest → register, guest skip → home (prices never walled), and
// openRegister returning true only after a successful register.
// Plugin-free: in-memory store + fake AuthApi, no HTTP / secure storage.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/auth/auth_controller.dart';
import 'package:shodasha_app/features/auth/auth_gate.dart';

class _FakeApi implements AuthApi {
  AuthSession _session() => AuthSession(
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(days: 30)),
    role: 'user',
  );

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String deviceId,
  }) async => _session();

  @override
  Future<AuthSession> demoLogin({
    required String phone,
    required String code,
    required String deviceId,
  }) async => _session();

  @override
  Future<void> logout(String accessToken) async {}
}

/// Store whose first read blocks, so the splash frame is deterministic.
class _GatedStore extends InMemorySessionStore {
  final Completer<void> gate = Completer<void>();

  @override
  Future<String?> readAccessToken() async {
    await gate.future;
    return super.readAccessToken();
  }
}

/// Store that never answers — the cold-start hang P2-1 guards against.
class _HangingStore extends InMemorySessionStore {
  final Completer<void> never = Completer<void>();

  @override
  Future<String?> readAccessToken() async {
    await never.future;
    return null;
  }
}

AuthController _controller(SessionStore store) {
  final controller = AuthController(
    api: _FakeApi(),
    store: store,
    deviceId: 'test-device',
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _saveValidSession(SessionStore store) => store.saveSession(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAtIso: DateTime.now()
      .add(const Duration(minutes: 5))
      .toIso8601String(),
  role: 'user',
);

Future<void> _pumpGate(WidgetTester tester, AuthController controller) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: AuthGate(
          controller: controller,
          home: const Scaffold(body: Center(child: Text('HOME'))),
        ),
      ),
    );

void main() {
  testWidgets('in-flight restore shows the splash, then home when valid', (
    tester,
  ) async {
    final store = _GatedStore();
    await _saveValidSession(store);
    final controller = _controller(store);

    await _pumpGate(tester, controller);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('HOME'), findsNothing);

    store.gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('Create your account'), findsNothing);
  });

  testWidgets('hung restore leaves the splash for login with a note', (
    tester,
  ) async {
    final controller = AuthController(
      api: _FakeApi(),
      store: _HangingStore(),
      deviceId: 'test-device',
      restoreTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);

    await _pumpGate(tester, controller);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(
      find.text('Couldn’t restore your session. Sign in again.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(controller.isAuthenticated, isFalse);
  });

  testWidgets('guest (no session) lands on register', (tester) async {
    final controller = _controller(InMemorySessionStore());
    await _pumpGate(tester, controller);
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    expect(controller.isAuthenticated, isFalse);
  });

  testWidgets('guest skip opens home without a session', (tester) async {
    final controller = _controller(InMemorySessionStore());
    await _pumpGate(tester, controller);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Browse without an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse without an account'));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
    expect(controller.isAuthenticated, isFalse);
  });

  testWidgets('openRegister returns true after a successful register', (
    tester,
  ) async {
    final controller = _controller(InMemorySessionStore());
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await openRegister(context, controller);
                },
                child: const Text('Open register'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open register'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Naya User');
    await tester.enterText(find.byType(TextField).at(1), 'naya@gmail.com');
    await tester.enterText(find.byType(TextField).at(2), '9876543210');
    await tester.pump();

    await tester.ensureVisible(find.text('Create Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(controller.isAuthenticated, isTrue);
    expect(result, isTrue);
    expect(find.text('Create your account'), findsNothing);
    expect(find.text('Open register'), findsOneWidget);
  });

  testWidgets('openRegister returns false when the user browses as guest', (
    tester,
  ) async {
    final controller = _controller(InMemorySessionStore());
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShodashaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await openRegister(context, controller);
                },
                child: const Text('Open register'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open register'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Browse without an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse without an account'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(controller.isAuthenticated, isFalse);
    expect(find.text('Create your account'), findsNothing);
  });
}
