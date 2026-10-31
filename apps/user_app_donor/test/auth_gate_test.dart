import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shodasha_donor/features/auth/auth_controller.dart';
import 'package:shodasha_donor/features/auth/auth_gate.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'cold boot without prior session mounts login screen without false error notice',
    (tester) async {
      final controller = AuthController(
        api: _NoopAuthApi(),
        store: InMemorySessionStore(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            controller: controller,
            home: const Scaffold(body: Text('HOME_SHELL')),
          ),
        ),
      );

      // Splash while restore is in flight
      expect(
        find.text('Pure 20L water delivered to your doorstep'),
        findsOneWidget,
      );

      // Let restoreSession complete and AuthGate switch from splash to login
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // Login screen mounted
      expect(find.text('Shodasha'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);

      // Must NOT show false negative restore failure notice
      expect(find.textContaining("Couldn't restore"), findsNothing);
      expect(find.textContaining('Sign in again'), findsNothing);
    },
  );

  testWidgets(
    'forced logout / session expiry notice is displayed on AuthGate',
    (tester) async {
      final store = InMemorySessionStore();
      final controller = AuthController(api: _NoopAuthApi(), store: store);
      addTearDown(controller.dispose);

      // Seed expired notice via forceLogout
      await controller.forceLogout(sessionExpired: true);

      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            controller: controller,
            home: const Scaffold(body: Text('HOME_SHELL')),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // Displays polite session notice
      expect(find.text('Please sign in to continue'), findsOneWidget);
    },
  );
}

class _NoopAuthApi implements AuthApi {
  @override
  Future<AuthSession> login({
    required String phone,
    required String password,
    required String deviceId,
  }) async => throw UnimplementedError();

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String deviceId,
  }) async => throw UnimplementedError();

  @override
  Future<AuthSession> refresh({required String refreshToken}) async =>
      throw UnimplementedError();

  @override
  Future<void> logout(String accessToken) async {}
}
