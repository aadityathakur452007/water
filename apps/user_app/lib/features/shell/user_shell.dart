// 032 — 5-tab shell: Home / Orders / Subscriptions / Wallet / Profile.
//
// Composition surface: the shell owns tab state + cross-tab routes and is
// the only place that imports multiple feature folders.
// Live slices: Orders (S5), Subscriptions (S6), Wallet (S7), Profile (S8).
// Home (S3) mounts its screen in the next wiring pass.
// Lazy mounting (ADR-112): a tab mounts on first visit and keeps its state
// after that via IndexedStack.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../orders/orders_controller.dart';
import '../orders/orders_screen.dart';
import '../profile/profile_controller.dart';
import '../profile/profile_screen.dart';
import '../subscriptions/subscription_screen.dart';
import '../support/support_screen.dart';
import '../wallet/payment_history_screen.dart';
import '../wallet/wallet_screen.dart';

/// Tab order is a stable identifier (deep links + tests).
enum UserTab { home, orders, subscriptions, wallet, profile }

class UserShell extends StatefulWidget {
  const UserShell({
    super.key,
    required this.api,
    required this.ordersController,
    required this.profileController,
    required this.isAuthenticated,
    required this.onLoginRequested,
    required this.onLogout,
    this.authListenable,
  });

  /// The single authenticated transport from the composition root.
  final ApiClient api;

  /// Auth changes must rebuild guest/auth tab bodies (Profile takes a bool).
  final Listenable? authListenable;

  final OrdersController ordersController;
  final ProfileController profileController;
  final bool Function() isAuthenticated;

  /// Pushes the register screen; resolves when the user leaves the route.
  final Future<void> Function(BuildContext context) onLoginRequested;

  /// Server revoke + local wipe live in the composition root.
  final Future<void> Function() onLogout;

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

  void _login() => widget.onLoginRequested(context);

  void _openPayments() => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PaymentHistoryScreen(api: widget.api),
        ),
      );

  void _openSupport() => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => SupportScreen(api: widget.api),
        ),
      );

  /// Dues payment lives in Wallet (S7) — the subscriptions strip only
  /// switches tabs (no cross-feature import).
  void _openWallet() => setState(() {
        _tab = UserTab.wallet;
        _mounted.add(UserTab.wallet);
      });

  @override
  Widget build(BuildContext context) {
    final listenable = widget.authListenable;
    return Scaffold(
      body: SafeArea(
        child: listenable == null
            ? _tabs()
            : ListenableBuilder(
                listenable: listenable,
                builder: (_, _) => _tabs(),
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

  Widget _tabs() => IndexedStack(
        index: _tab.index,
        children: [
          for (final tab in UserTab.values)
            _mounted.contains(tab)
                ? _bodyFor(tab)
                : const SizedBox.shrink(),
        ],
      );

  Widget _bodyFor(UserTab tab) => switch (tab) {
        UserTab.home => const _TabBody(tab: UserTab.home),
        UserTab.orders => OrdersScreen(
            controller: widget.ordersController,
            isAuthenticated: widget.isAuthenticated,
            onOpenPayments: _openPayments,
            onSupport: _openSupport,
          ),
        UserTab.subscriptions => widget.isAuthenticated()
            ? SubscriptionScreen(
                api: widget.api,
                onOpenWallet: _openWallet,
              )
            : _GuestBody(
                icon: Icons.event_repeat_outlined,
                title: 'Subscriptions',
                message: 'Sign in to see your plans and dues.',
                onSignIn: _login,
              ),
        UserTab.wallet => WalletScreen(
            api: widget.api,
            isAuthenticated: widget.isAuthenticated,
            onLoginRequired: _login,
          ),
        UserTab.profile => ProfileScreen(
            api: widget.api,
            isAuthenticated: widget.isAuthenticated(),
            controller: widget.profileController,
            onLoginRequired: _login,
            onLogout: widget.onLogout,
            onOpenPayments: _openPayments,
          ),
      };
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

/// Guest gate for tabs whose data is account-scoped (Subscriptions): no
/// authed request until login, honest copy instead of a fake empty list.
class _GuestBody extends StatelessWidget {
  const _GuestBody({
    required this.icon,
    required this.title,
    required this.message,
    required this.onSignIn,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ShodashaTheme.muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onSignIn,
              style: OutlinedButton.styleFrom(
                foregroundColor: ShodashaTheme.teal,
                minimumSize: const Size(0, 48),
              ),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
