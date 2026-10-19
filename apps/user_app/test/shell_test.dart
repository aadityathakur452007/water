// S1 shell spec: 5 stable tabs, lazy mount (ADR-112), honest placeholders.
// Plugin-free.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shodasha_app/core/theme.dart';
import 'package:shodasha_app/features/shell/user_shell.dart';

void main() {
  Finder navLabel(String label) => find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );

  Future<void> pumpShell(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(theme: buildShodashaTheme(), home: const UserShell()),
      );

  testWidgets('shell: 5 tabs in stable order, only Home mounted first',
      (tester) async {
    await pumpShell(tester);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(navLabel('Home'), findsOneWidget);
    expect(navLabel('Orders'), findsOneWidget);
    expect(navLabel('Subscriptions'), findsOneWidget);
    expect(navLabel('Wallet'), findsOneWidget);
    expect(navLabel('Profile'), findsOneWidget);
    // Lazy mount: one placeholder (Home) until another tab is visited.
    expect(find.text('Coming soon.'), findsOneWidget);
  });

  testWidgets('shell: visiting a tab mounts it once and keeps state',
      (tester) async {
    await pumpShell(tester);
    // Inactive IndexedStack children are offstage: count with them included.
    Finder mountedPlaceholders() =>
        find.text('Coming soon.', skipOffstage: false);
    int visibleTab() =>
        tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

    await tester.tap(navLabel('Wallet'));
    await tester.pumpAndSettle();
    expect(visibleTab(), UserTab.wallet.index);
    expect(mountedPlaceholders(), findsNWidgets(2));
    // Back to Home, then to a third tab: mounted set grows, never remounts.
    await tester.tap(navLabel('Home'));
    await tester.pumpAndSettle();
    expect(visibleTab(), UserTab.home.index);
    expect(mountedPlaceholders(), findsNWidgets(2));
    await tester.tap(navLabel('Subscriptions'));
    await tester.pumpAndSettle();
    expect(visibleTab(), UserTab.subscriptions.index);
    expect(mountedPlaceholders(), findsNWidgets(3));
  });
}
