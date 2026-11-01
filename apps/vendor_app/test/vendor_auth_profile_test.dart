import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/core/api_client.dart';
import 'package:vendor_app/features/auth/auth_controller.dart';
import 'package:vendor_app/features/auth/vendor_code_screen.dart';
import 'package:vendor_app/features/profile/profile_screen.dart';
import 'package:vendor_app/shared/ui/app_button.dart';

MockClient _mockClient() => MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/vendor/leaves')) {
        return http.Response(
          jsonEncode({
            'leaves': [
              {
                'id': 'l-1',
                'start_date': '2026-11-05',
                'end_date': '2026-11-06',
                'reason': 'Family function',
                'status': 'pending',
              }
            ]
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

class _FakeAuthApi implements AuthApi {
  @override
  Future<AuthSession> vendorCodeLogin({
    required String phone,
    required String code,
    required String deviceId,
  }) async {
    return AuthSession(
      accessToken: 'tok',
      refreshToken: 'ref',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      role: 'vendor',
    );
  }

  @override
  Future<void> logout(String accessToken) async {}

  @override
  Future<AuthSession> refreshSession({
    required String refreshToken,
    required String deviceId,
  }) async {
    return AuthSession(
      accessToken: 'tok',
      refreshToken: 'ref',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      role: 'vendor',
    );
  }
}

void main() {
  testWidgets('VendorCodeScreen renders canonical AppButtons for login and WhatsApp', (tester) async {
    final controller = AuthController(
      api: _FakeAuthApi(),
      store: InMemorySessionStore(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VendorCodeScreen(controller: controller),
      ),
    );

    expect(find.byType(AppButton), findsNWidgets(2));
    expect(find.text('Login karein'), findsOneWidget);
    expect(find.text('Admin WhatsApp Support: 7828442476'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('ProfileScreen renders canonical AppButtons for save, leave, whatsapp and logout', (tester) async {
    final apiClient = ApiClient(client: _mockClient(), deviceId: 'test-device');
    final authController = AuthController(
      api: _FakeAuthApi(),
      store: InMemorySessionStore(),
    );

    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          auth: authController,
          meLoader: () async => {
            'user': {'name': 'Ramu Driver', 'phone': '+919302190067'},
            'profile': {
              'address': 'Bhopal Central Hub',
              'hours': '8-8',
              'vehicle_type': '3 Wheeler',
              'vehicle_number': 'MP04-AB-1234',
            },
          },
          profileLoader: () async => {
            'name': 'Ramu Driver',
            'phone': '+919302190067',
            'address': 'Bhopal Central Hub',
            'hours': '8-8',
          },
          profileSaver: (fields) async => fields,
          api: apiClient,
        ),
      ),
    );

    // Initial pump and wait for future to settle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Ramu Driver'), findsWidgets);
    expect(find.text('+919302190067'), findsWidgets);

    // Verify AppButtons on ProfileScreen
    expect(find.byType(AppButton), findsWidgets);
    expect(find.text('Save karein'), findsOneWidget);
    expect(find.text('Nayi Chutti Request Karein'), findsOneWidget);
    expect(find.text('WhatsApp help ($kSupportPhone)'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);

    authController.dispose();
  });
}
