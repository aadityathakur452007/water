import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/core/theme.dart';
import 'package:shodasha_donor/features/addresses/address_screen.dart';
import 'package:shodasha_donor/features/auth/auth_controller.dart';
import 'package:shodasha_donor/features/auth/login_screen.dart';
import 'package:shodasha_donor/features/legal/privacy_policy_screen.dart';
import 'package:shodasha_donor/features/profile/donor_profile_screen.dart';
import 'package:shodasha_donor/features/profile/profile_controller.dart';
import 'package:shodasha_donor/features/subscriptions/plan_builder_sheet.dart';
import 'package:shodasha_donor/features/subscriptions/subscription_controller.dart';

void main() {
  group('₹650 Jar Damage Agreement & Privacy Policy Integrations', () {
    testWidgets(
      'plan builder requires checking ₹650 jar damage agreement before submission',
      (WidgetTester tester) async {
        final api = _FakeDamageApi();

        await tester.pumpWidget(
          MaterialApp(
            theme: buildShodashaTheme(),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => showPlanBuilderSheet(ctx, api: api),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // 1. Verify ₹650 damage agreement text exists
        expect(
          find.text('I agree to pay ₹650 if the jar is damaged or lost.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('20L water jars are reusable assets delivered without advance deposit'),
          findsOneWidget,
        );

        // 2. Select monthly bill and COD
        await tester.ensureVisible(find.text('Monthly bill'));
        await tester.tap(find.text('Monthly bill'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Cash on delivery'));
        await tester.tap(find.text('Cash on delivery'));
        await tester.pumpAndSettle();

        // 3. Before checking the box, submit button should not trigger create
        await tester.ensureVisible(find.text(subStrings['startPlan']!));
        await tester.tap(find.text(subStrings['startPlan']!));
        await tester.pumpAndSettle();

        expect(api.createCalls, 0);

        // 4. Tap the checkbox to agree
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();

        // 5. Now submit succeeds
        await tester.ensureVisible(find.text(subStrings['startPlan']!));
        await tester.tap(find.text(subStrings['startPlan']!));
        await tester.pumpAndSettle();

        expect(api.createCalls, 1);
      },
    );

    testWidgets('donor profile screen provides entry point to Privacy Policy & Terms', (
      WidgetTester tester,
    ) async {
      final auth = AuthController(
        api: _StubAuthApi(),
        store: InMemorySessionStore(),
        deviceId: 'test-device',
      );
      final profile = ProfileController(api: _FakeDamageApi());
      final address = AddressController(api: _FakeDamageApi());

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: DonorProfileScreen(
            auth: auth,
            controller: profile,
            addressController: address,
            orderCount: 4,
            onOpenWallet: () {},
            onOpenNotifications: () {},
            onOpenSupport: () {},
            onOpenSubscriptions: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Privacy Policy & Terms'),
        200,
      );
      expect(find.text('Privacy Policy & Terms'), findsOneWidget);
      expect(
        find.text('DPDP Act 2023 · Data security · Grievance'),
        findsOneWidget,
      );

      await tester.tap(find.text('Privacy Policy & Terms'));
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
    });

    testWidgets('login screen provides interactive link to Terms & Privacy Policy', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auth = AuthController(
        api: _StubAuthApi(),
        store: InMemorySessionStore(),
        deviceId: 'test-device',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildShodashaTheme(),
          home: DonorLoginScreen(controller: auth),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.textContaining('Terms & Privacy Policy'));
      expect(find.textContaining('Terms & Privacy Policy'), findsOneWidget);

      await tester.tap(find.textContaining('Terms & Privacy Policy'));
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
    });
  });
}

class _FakeDamageApi extends ApiClient {
  _FakeDamageApi() : super(accessToken: 'damage-test-token');

  int createCalls = 0;

  @override
  Future<List<dynamic>> listAddresses() async => [
    {'id': 'addr-1', 'label': 'Home · Bhopal', 'pincode': '462001'},
  ];

  @override
  Future<Map<String, dynamic>> subscriptionEstimate({
    required int qty,
    required String skuMix,
  }) async => {
    'water_bill': 2800,
    'deposit_due': 0,
    'total': 2800,
    'monthly_topup_paise': 84000,
    'rate_version': 'v1',
  };

  @override
  Future<Map<String, dynamic>> createSubscription({
    required String addressId,
    required int qty,
    required String skuMix,
    required String window,
    required String scheduleType,
    String recurrence = '',
    String billingMode = 'per_delivery',
    String paymentMethod = 'cod',
    String? idempotencyKey,
  }) async {
    createCalls++;
    return {
      'id': 'sub-test-1',
      'status': 'active',
    };
  }

  @override
  Future<Map<String, dynamic>> me() async => {
    'user': {
      'id': 'usr-1',
      'name': 'Rahul Sharma',
      'phone': '+919876543210',
      'email': 'rahul@example.com',
    },
  };
}

class _StubAuthApi implements AuthApi {
  @override
  Future<AuthSession> login({
    required String phone,
    required String password,
    required String deviceId,
  }) async => AuthSession(
    accessToken: 'test-token',
    refreshToken: 'refresh-token',
    expiresAt: DateTime.now().add(const Duration(days: 30)),
    role: 'user',
  );

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String deviceId,
  }) async => AuthSession(
    accessToken: 'test-token',
    refreshToken: 'refresh-token',
    expiresAt: DateTime.now().add(const Duration(days: 30)),
    role: 'user',
  );

  @override
  Future<AuthSession> refresh({required String refreshToken}) async =>
      throw UnimplementedError();

  @override
  Future<void> logout(String accessToken) async {}
}
