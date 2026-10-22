import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/features/auth/auth_controller.dart';
import 'package:shodasha_donor/features/auth/login_screen.dart';

void main() {
  testWidgets('login screen is customer-only and fits a 360dp phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AuthController(
      api: _StubAuthApi(),
      store: InMemorySessionStore(),
      deviceId: 'test-device',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: DonorLoginScreen(controller: controller)),
    );

    expect(find.textContaining('SHODASHA'), findsWidgets);
    expect(find.text('Get Verification Code'), findsOneWidget);
    expect(find.text('Demo access (QA)'), findsOneWidget);
    expect(find.textContaining('Partner'), findsNothing);
    expect(find.textContaining('Rider'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _StubAuthApi implements AuthApi {
  @override
  Future<OtpStartResult> startOtp({required String phone}) async =>
      const OtpStartResult(channel: 'fast2sms', resendAfterSeconds: 30);

  @override
  Future<AuthSession> verifyOtp({
    required String phone,
    required String code,
    required String deviceId,
  }) async => AuthSession(
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(days: 1)),
    role: 'user',
  );

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String deviceId,
  }) async => throw UnimplementedError();

  @override
  Future<AuthSession> demoLogin({
    required String phone,
    required String code,
    required String deviceId,
  }) async => throw UnimplementedError();

  @override
  Future<void> logout(String accessToken) async {}
}
