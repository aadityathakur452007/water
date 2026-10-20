// Shell spec: 5 stable tabs, lazy mount (ADR-112), real tab bodies in guest
// mode (Home / Orders / Wallet / Profile) with zero authed requests.
// Plugin-free.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/addresses/address_screen.dart';
import 'package:shodasha_app/features/booking/booking_controller.dart';
import 'package:shodasha_app/features/booking/home_screen.dart';
import 'package:shodasha_app/features/orders/orders_controller.dart';
import 'package:shodasha_app/features/orders/orders_screen.dart';
import 'package:shodasha_app/features/profile/profile_controller.dart';
import 'package:shodasha_app/features/profile/profile_screen.dart';
import 'package:shodasha_app/features/shell/user_shell.dart';
import 'package:shodasha_app/features/subscriptions/subscription_screen.dart';
import 'package:shodasha_app/features/wallet/wallet_screen.dart';

/// Test-only catalog snapshot so Home does not hit the network.
class _StubCatalog implements CatalogApi {
  @override
  Future<CatalogRates> fetchRates() async => const CatalogRates(
        refillPaise: 2800,
        containerPaise: 3000,
        depositPaise: 15000,
        capPaise: 300,
      );
}

void main() {
  Finder navLabel(String label) => find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );

  Widget buildShell() {
    final api = ApiClient(deviceId: 'test-device');
    return MaterialApp(
      theme: buildShodashaTheme(),
      home: UserShell(
        api: api,
        bookingController: BookingController(catalog: _StubCatalog()),
        addresses: AddressController(api: api),
        ordersController: OrdersController(repo: StubOrdersRepository()),
        profileController: ProfileController(api: api),
        isAuthenticated: () => false,
        onLoginRequested: (_) async => false,
        onLogout: () async {},
      ),
    );
  }

  int visibleTab(WidgetTester tester) =>
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

  testWidgets('shell: 5 tabs in stable order, only Home mounted first',
      (tester) async {
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(navLabel('Home'), findsOneWidget);
    expect(navLabel('Orders'), findsOneWidget);
    expect(navLabel('Subscriptions'), findsOneWidget);
    expect(navLabel('Wallet'), findsOneWidget);
    expect(navLabel('Profile'), findsOneWidget);
    // Lazy mount: Home is the only tab built.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OrdersScreen, skipOffstage: false), findsNothing);
    expect(find.byType(WalletScreen, skipOffstage: false), findsNothing);
    expect(find.byType(ProfileScreen, skipOffstage: false), findsNothing);
  });

  testWidgets('shell: visiting a tab mounts it once and keeps state',
      (tester) async {
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    await tester.tap(navLabel('Orders'));
    await tester.pumpAndSettle();
    expect(visibleTab(tester), UserTab.orders.index);
    expect(find.byType(OrdersScreen), findsOneWidget);

    // Back to Home: Orders stays mounted (offstage), never remounts.
    await tester.tap(navLabel('Home'));
    await tester.pumpAndSettle();
    expect(visibleTab(tester), UserTab.home.index);
    expect(find.byType(OrdersScreen, skipOffstage: false), findsOneWidget);

    await tester.tap(navLabel('Wallet'));
    await tester.pumpAndSettle();
    expect(visibleTab(tester), UserTab.wallet.index);
    expect(find.byType(WalletScreen), findsOneWidget);

    // Subscriptions is account-scoped: guest sees a sign-in gate and the
    // screen (which would fetch) stays unmounted.
    await tester.tap(navLabel('Subscriptions'));
    await tester.pumpAndSettle();
    expect(visibleTab(tester), UserTab.subscriptions.index);
    expect(find.text('Sign in to see your plans and dues.'), findsOneWidget);
    expect(
        find.byType(SubscriptionScreen, skipOffstage: false), findsNothing);

    await tester.tap(navLabel('Profile'));
    await tester.pumpAndSettle();
    expect(visibleTab(tester), UserTab.profile.index);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });
}
