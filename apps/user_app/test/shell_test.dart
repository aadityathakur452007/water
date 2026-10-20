// Shell spec: 5 stable tabs, lazy mount (ADR-112), real tab bodies in guest
// mode (Orders / Wallet / Profile) with zero network. Plugin-free.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shodasha_app/core/api_client.dart';
import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/orders/orders_controller.dart';
import 'package:shodasha_app/features/orders/orders_screen.dart';
import 'package:shodasha_app/features/profile/profile_controller.dart';
import 'package:shodasha_app/features/profile/profile_screen.dart';
import 'package:shodasha_app/features/shell/user_shell.dart';
import 'package:shodasha_app/features/wallet/wallet_screen.dart';

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
        ordersController: OrdersController(repo: StubOrdersRepository()),
        profileController: ProfileController(api: api),
        isAuthenticated: () => false,
        onLoginRequested: (_) async {},
        onLogout: () async {},
      ),
    );
  }

  int visibleTab(WidgetTester tester) =>
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

  testWidgets('shell: 5 tabs in stable order, only Home mounted first',
      (tester) async {
    await tester.pumpWidget(buildShell());
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(navLabel('Home'), findsOneWidget);
    expect(navLabel('Orders'), findsOneWidget);
    expect(navLabel('Subscriptions'), findsOneWidget);
    expect(navLabel('Wallet'), findsOneWidget);
    expect(navLabel('Profile'), findsOneWidget);
    // Lazy mount: one placeholder (Home) until another tab is visited.
    expect(find.text('Coming soon.'), findsOneWidget);
    expect(find.byType(OrdersScreen, skipOffstage: false), findsNothing);
    expect(find.byType(WalletScreen, skipOffstage: false), findsNothing);
    expect(find.byType(ProfileScreen, skipOffstage: false), findsNothing);
  });

  testWidgets('shell: visiting a tab mounts it once and keeps state',
      (tester) async {
    await tester.pumpWidget(buildShell());

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

    // Subscriptions is still a placeholder; Home + Subscriptions = 2.
    await tester.tap(navLabel('Subscriptions'));
    await tester.pumpAndSettle();
    expect(visibleTab(tester), UserTab.subscriptions.index);
    expect(find.text('Coming soon.', skipOffstage: false), findsNWidgets(2));
    expect(find.byType(ProfileScreen, skipOffstage: false), findsNothing);
  });
}
