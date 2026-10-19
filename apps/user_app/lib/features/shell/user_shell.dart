// S1 — 5-tab shell: Home / Orders / Subscriptions / Wallet / Profile.
//
// Structure mirrors the donor bottom-nav map; chrome uses the locked theme
// (teal structure, slate ground). Tab bodies land per slice:
//   S3 home · S5 orders · S6 subscriptions · S7 wallet · S8 profile.
// Lazy mounting (ADR-112): a tab mounts on first visit and keeps its state
// after that via IndexedStack.

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Tab order is a stable identifier (deep links + tests).
enum UserTab { home, orders, subscriptions, wallet, profile }

class UserShell extends StatefulWidget {
  const UserShell({super.key});

  @override
  State<UserShell> createState() => _UserShellState();
}

class _UserShellState extends State<UserShell> {
  UserTab _tab = UserTab.home;

  /// Tabs visited at least once (lazy mount).
  final Set<UserTab> _mounted = {UserTab.home};

  void _select(int index) {
    final tab = UserTab.values[index];
    setState(() {
      _tab = tab;
      _mounted.add(tab);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab.index,
          children: [
            for (final tab in UserTab.values)
              _mounted.contains(tab)
                  ? _TabBody(tab: tab)
                  : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_repeat_outlined),
            selectedIcon: Icon(Icons.event_repeat),
            label: 'Subscriptions',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Wallet',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Honest placeholder until the tab's slice lands — no fake data, no fake
/// numbers (States.md: an empty screen says why it is empty).
class _TabBody extends StatelessWidget {
  const _TabBody({required this.tab});

  final UserTab tab;

  @override
  Widget build(BuildContext context) {
    final (icon, title) = switch (tab) {
      UserTab.home => (Icons.home_outlined, 'Home'),
      UserTab.orders => (Icons.receipt_long_outlined, 'Orders'),
      UserTab.subscriptions =>
        (Icons.event_repeat_outlined, 'Subscriptions'),
      UserTab.wallet => (Icons.account_balance_wallet_outlined, 'Wallet'),
      UserTab.profile => (Icons.person_outline, 'Profile'),
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: ShodashaTheme.teal),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ShodashaTheme.ink,
                ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Coming soon.',
            style: TextStyle(color: ShodashaTheme.muted),
          ),
        ],
      ),
    );
  }
}
