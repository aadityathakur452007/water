import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/features/auth/auth_controller.dart';
import 'package:shodasha_donor/features/auth/login_screen.dart';

void main() {
  testWidgets('sign-in is mobile + password and fits a 360dp phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _controller(_StubAuthApi());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: DonorLoginScreen(controller: controller)),
    );

    expect(find.textContaining('Shodasha'), findsWidgets);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Mobile number'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Try the demo (no registration)'), findsOneWidget);
    expect(find.textContaining('Verification'), findsNothing);
    expect(find.textContaining('Partner'), findsNothing);
    expect(find.textContaining('Rider'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'create mode asks for name, optional email and confirm password',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = _controller(_StubAuthApi());
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: DonorLoginScreen(controller: controller)),
      );

      final createLink = find.text('New here? Create account');
      await tester.ensureVisible(createLink);
      await tester.tap(createLink);
      await tester.pumpAndSettle();

      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Email (optional)'), findsOneWidget);
      expect(find.text('Confirm password'), findsWidgets);
      expect(find.text('Create account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty sign-in shows inline phone and password errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _controller(_StubAuthApi());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: DonorLoginScreen(controller: controller)),
    );

    final signIn = find.text('Sign in').last;
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Enter a valid 10-digit mobile number (digits only, starting 6–9)',
      ),
      findsOneWidget,
    );
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(controller.isAuthenticated, isFalse);
  });

  testWidgets('valid sign-in calls the password API once', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _StubAuthApi();
    final controller = _controller(api);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: DonorLoginScreen(controller: controller)),
    );

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '98765 43210');
    await tester.enterText(fields.at(1), 'water123');

    final signIn = find.text('Sign in').last;
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await tester.pumpAndSettle();

    expect(api.loginPhone, '+919876543210');
    expect(api.loginPassword, 'water123');
    expect(controller.isAuthenticated, isTrue);
  });
}

AuthController _controller(_StubAuthApi api) => AuthController(
  api: api,
  store: InMemorySessionStore(),
  deviceId: 'test-device',
);

class _StubAuthApi implements AuthApi {
  String? loginPhone;
  String? loginPassword;

  @override
  Future<AuthSession> login({
    required String phone,
    required String password,
    required String deviceId,
  }) async {
    loginPhone = phone;
    loginPassword = password;
    return AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      role: 'user',
    );
  }

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String deviceId,
  }) async => throw UnimplementedError();

  @override
  Future<AuthSession> demoLogin({
    required String phone,
    required String code,
    required String deviceId,
  }) async => throw UnimplementedError();

  @override
  Future<AuthSession> refresh({required String refreshToken}) async =>
      throw UnimplementedError();

  @override
  Future<void> logout(String accessToken) async {}
}
