import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodasha_donor/core/api_client.dart';
import 'package:shodasha_donor/features/addresses/address_screen.dart';
import 'package:shodasha_donor/features/auth/auth_controller.dart';
import 'package:shodasha_donor/features/booking/booking_controller.dart';
import 'package:shodasha_donor/features/orders/orders_controller.dart';
import 'package:shodasha_donor/features/profile/profile_controller.dart';
import 'package:shodasha_donor/features/shell/donor_shell.dart';

void main() {
  testWidgets('donor shell mounts and opens all five real tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeApi();
    final auth = AuthController(
      api: _FakeAuthApi(),
      store: InMemorySessionStore(),
      deviceId: 'test-device',
    );
    addTearDown(auth.dispose);
    await auth.login(rawPhone: '9876543210', password: 'test-pass1');

    final booking = BookingController(
      initialRates: const CatalogRates(
        refillPaise: 2800,
        containerPaise: 3000,
        depositPaise: 15000,
        capPaise: 300,
      ),
    );
    final addresses = AddressController(api: api);
    final orders = OrdersController(repo: ApiBackedOrdersRepository(api));
    final profile = ProfileController(api: api);

    await tester.pumpWidget(
      MaterialApp(
        home: DonorShell(
          api: api,
          auth: auth,
          booking: booking,
          addresses: addresses,
          orders: orders,
          profile: profile,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pure water, delivered.'), findsOneWidget);
    expect(_tabIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(_tabIcon(Icons.calendar_month_outlined), findsOneWidget);
    expect(_tabIcon(Icons.account_balance_wallet_outlined), findsOneWidget);
    expect(_tabIcon(Icons.person_outline_rounded), findsOneWidget);

    await tester.tap(_tabIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    expect(find.text('My orders'), findsOneWidget);

    await tester.tap(_tabIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Subscriptions'), findsWidgets);

    await tester.tap(_tabIcon(Icons.account_balance_wallet_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Wallet'), findsWidgets);

    await tester.tap(_tabIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsWidgets);

    await tester.tap(_tabIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Pure water, delivered.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _tabIcon(IconData icon) => find.descendant(
  of: find.byType(NavigationBar),
  matching: find.byIcon(icon),
);

class _FakeApi extends ApiClient {
  _FakeApi()
    : super(
        baseUrl: 'http://127.0.0.1/v1',
        deviceId: 'test-device',
        accessTokenGetter: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> catalog({bool allowStale = false}) async => {
    'skus': [
      {'id': 'refill', 'price_paise': 2800},
      {'id': 'container', 'price_paise': 3000},
    ],
    'deposit_per_jar': 15000,
    'cap_charge': 300,
  };

  @override
  Future<Map<String, dynamic>> me() async => {
    'name': 'Test Customer',
    'phone': '+919876543210',
    'email': 'test@example.com',
  };

  @override
  Future<Map<String, dynamic>> ledgerMe() async => {
    'held': 0,
    'deposit_paid': 0,
    'deposit_refunded': 0,
    'wallet_held': 0,
    'dues': 0,
  };

  @override
  Future<List<dynamic>> listAddresses() async => const [];

  @override
  Future<List<dynamic>> listSubscriptions() async => const [];

  @override
  Future<Map<String, dynamic>> billingDues() async => {'dues': 0};

  @override
  Future<Map<String, dynamic>> listOrders({
    String? cursor,
    int limit = 20,
  }) async => {'data': <dynamic>[], 'next_cursor': null};

  @override
  Future<List<dynamic>> listUserPayments({int limit = 50}) async => const [];

  @override
  Future<List<dynamic>> listComplaints() async => const [];
}

class _FakeAuthApi implements AuthApi {
  @override
  Future<AuthSession> login({
    required String phone,
    required String password,
    required String deviceId,
  }) async => AuthSession(
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
