// Shell spec: 5 stable tabs, lazy mount (ADR-112), account-scoped tabs
// (Orders / Subscriptions) guest-gated with zero authed requests.
// Plugin-free.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

  Widget buildShell({ApiClient? api}) {
    final client = api ?? ApiClient(deviceId: 'test-device');
    return MaterialApp(
      theme: buildShodashaTheme(),
      home: UserShell(
        api: client,
        bookingController: BookingController(catalog: _StubCatalog()),
        addresses: AddressController(api: client),
        ordersController: OrdersController(repo: StubOrdersRepository()),
        profileController: ProfileController(api: client),
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
    // Orders is account-scoped: guests get the sign-in gate and the screen
    // (which would render cached rows) is never mounted.
    expect(find.text('Sign in to see your orders.'), findsOneWidget);
    expect(find.byType(OrdersScreen, skipOffstage: false), findsNothing);

    // Back to Home: Home stays mounted (offstage), never remounts.
    await tester.tap(navLabel('Home'));
    await tester.pumpAndSettle();
    expect(visibleTab(tester), UserTab.home.index);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OrdersScreen, skipOffstage: false), findsNothing);

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

  testWidgets('shell: back on a sub-tab returns Home', (tester) async {
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    await tester.tap(navLabel('Wallet'));
    await tester.pumpAndSettle();
    expect(visibleTab(tester), UserTab.wallet.index);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(visibleTab(tester), UserTab.home.index);
  });

  testWidgets('shell: wide screens cap body and nav at 560 and center them',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    for (final key in const ['shell-body', 'shell-nav']) {
      final box = find.byKey(ValueKey(key));
      expect(tester.getSize(box).width, 560);
      expect(tester.getTopLeft(box).dx, 320);
    }
  });

  testWidgets('shell: offline strip retries and confirms recovery',
      (tester) async {
    var catalogCalls = 0;
    final api = ApiClient(
      client: MockClient((req) async {
        catalogCalls++;
        return http.Response('{"ok":true}', 200);
      }),
      deviceId: 'test-device',
    );
    await tester.pumpWidget(buildShell(api: api));
    await tester.pumpAndSettle();

    api.offline.value = true;
    await tester.pump();
    expect(find.textContaining('No internet'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(catalogCalls, 1);
    expect(api.offline.value, isFalse);
    expect(find.text('Back online.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Back online.'), findsNothing);
  });
}
