import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/core/theme.dart';
import 'package:shodasha_donor/features/addresses/address_screen.dart';
import 'package:shodasha_donor/features/auth/auth_controller.dart';
import 'package:shodasha_donor/features/profile/donor_profile_screen.dart';
import 'package:shodasha_donor/features/profile/profile_controller.dart';

class _FakeProfileApi extends ApiClient {
  _FakeProfileApi() : super(accessToken: 'test-token');

  @override
  Future<Map<String, dynamic>> me() async => {
        'id': 'usr-1',
        'name': 'Aditya Thakur',
        'phone': '7828442476',
        'email': 'aditya@example.com',
      };

  @override
  Future<List<dynamic>> listAddresses() async => [
        {
          'id': 'addr-1',
          'label': 'Home',
          'type': 'home',
          'phone': '7828442476',
          'pincode': '462001',
          'formatted': '123, Main Road, Bhopal',
          'landmark': 'Near Park',
          'has_lift': true,
          'is_default': true,
          'lat': 23.2599,
          'lng': 77.4126,
        },
      ];
}

class _FakeAuthApi implements AuthApi {
  @override
  Future<AuthSession> login({
    required String phone,
    required String password,
    required String deviceId,
  }) async =>
      AuthSession(
        accessToken: 'test-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
        role: 'user',
      );

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String deviceId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<AuthSession> refresh({required String refreshToken}) async =>
      throw UnimplementedError();

  @override
  Future<void> logout(String accessToken) async {}
}

void main() {
  testWidgets('DonorProfileScreen renders surface AppBar and 2 clean customer stats without session vanity', (
    tester,
  ) async {
    final api = _FakeProfileApi();
    final auth = AuthController(
      api: _FakeAuthApi(),
      store: InMemorySessionStore(),
      deviceId: 'test-device',
    );
    addTearDown(auth.dispose);
    await auth.login(rawPhone: '7828442476', password: 'test-pass1');

    final profile = ProfileController(api: api);
    final addresses = AddressController(api: api);

    await profile.load();
    await addresses.load();

    await tester.pumpWidget(
      MaterialApp(
        home: DonorProfileScreen(
          auth: auth,
          controller: profile,
          addressController: addresses,
          orderCount: 5,
          onOpenWallet: () {},
          onOpenNotifications: () {},
          onOpenSupport: () {},
          onOpenSubscriptions: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify AppBar uses ShodashaTheme.surface and ShodashaTheme.ink
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, ShodashaTheme.surface);
    expect(appBar.foregroundColor, ShodashaTheme.ink);

    // 2. Verify identity card info
    expect(find.text('Aditya Thakur'), findsOneWidget);
    expect(find.text('7828442476'), findsOneWidget);
    expect(find.text('aditya@example.com'), findsOneWidget);

    // 3. Verify 2 customer stats are rendered
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Addresses'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // 4. Verify vanity "Session: Active" is omitted
    expect(find.text('Session'), findsNothing);
    expect(find.text('Active'), findsNothing);
  });

  testWidgets('Tapping Water quality opens modal with sanitized Bhopal purification copy', (
    tester,
  ) async {
    final api = _FakeProfileApi();
    final auth = AuthController(
      api: _FakeAuthApi(),
      store: InMemorySessionStore(),
      deviceId: 'test-device',
    );
    addTearDown(auth.dispose);
    await auth.login(rawPhone: '7828442476', password: 'test-pass1');

    final profile = ProfileController(api: api);
    final addresses = AddressController(api: api);

    await profile.load();
    await addresses.load();

    await tester.pumpWidget(
      MaterialApp(
        home: DonorProfileScreen(
          auth: auth,
          controller: profile,
          addressController: addresses,
          orderCount: 0,
          onOpenWallet: () {},
          onOpenNotifications: () {},
          onOpenSupport: () {},
          onOpenSubscriptions: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll until Water quality tile is visible
    await tester.scrollUntilVisible(
      find.text('Water quality'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    // Tap Water quality tile
    await tester.tap(find.text('Water quality'));
    await tester.pumpAndSettle();

    // Verify modal title and sanitized copy
    expect(find.text('Water quality'), findsWidgets);
    expect(
      find.textContaining('Every Shodasha 20L can undergoes automated 9-stage purification'),
      findsOneWidget,
    );
    expect(find.textContaining('live plant telemetry'), findsNothing);
    expect(find.textContaining('API does not expose it'), findsNothing);
  });
}
