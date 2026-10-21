// 032 — 5-tab shell: Home / Orders / Subscriptions / Wallet / Profile.
//
// Composition surface: the shell owns tab state + cross-tab routes and is
// the only place that imports multiple feature folders. All five tabs are
// live; account-scoped tabs are guest-gated so no authed request fires
// before login (States.md auth states).
//
// Lazy mounting (ADR-112): a tab mounts on first visit and keeps its state
// after that via IndexedStack.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../addresses/address_screen.dart';
import '../booking/booking_controller.dart';
import '../booking/booking_sheet.dart';
import '../booking/home_screen.dart';
import '../booking/quote_confirm.dart';
import '../orders/orders_controller.dart';
import '../orders/orders_screen.dart';
import '../profile/profile_controller.dart';
import '../profile/profile_screen.dart';
import '../returns/return_sheet.dart';
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
    required this.bookingController,
    required this.addresses,
    required this.ordersController,
    required this.profileController,
    required this.isAuthenticated,
    required this.onLoginRequested,
    required this.onLogout,
    this.razorpayKeyId = '',
    this.authListenable,
  });

  /// The single authenticated transport from the composition root.
  final ApiClient api;

  /// Auth changes must rebuild guest/auth tab bodies (Profile takes a bool)
  /// and refresh the ledger used by the COD gate.
  final Listenable? authListenable;

  final BookingController bookingController;
  final AddressController addresses;
  final OrdersController ordersController;
  final ProfileController profileController;

  final bool Function() isAuthenticated;

  /// Pushes the register screen; true when the user ends up authenticated.
  final Future<bool> Function(BuildContext context) onLoginRequested;

  /// Server revoke + local wipe live in the composition root.
  final Future<void> Function() onLogout;

  /// Publishable Razorpay key (--dart-define RAZORPAY_KEY_ID).
  final String razorpayKeyId;

  @override
  State<UserShell> createState() => _UserShellState();
}

class _UserShellState extends State<UserShell> {
  UserTab _tab = UserTab.home;

  /// Tabs visited at least once (lazy mount).
  final Set<UserTab> _mounted = {UserTab.home};

  @override
  void initState() {
    super.initState();
    widget.authListenable?.addListener(_onAuthChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLedger());
  }

  @override
  void dispose() {
    widget.authListenable?.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!widget.isAuthenticated()) return;
    _refreshLedger();
    // Guest → login happens on top of the live shell, so Home is already
    // mounted and its guest-gated address fetch still needs to run.
    if (widget.addresses.status == AddrStatus.initial) {
      widget.addresses.load();
    }
  }

  /// Live dues/held/deposit into booking so the COD gate + deposit display
  /// match the server (014). Best-effort — Home keeps its honest states.
  Future<void> _refreshLedger() async {
    if (!mounted || !widget.isAuthenticated()) return;
    try {
      final led = await widget.api.ledgerMe();
      // Session may have ended while the call was in flight — never write
      // the previous account's dues into the next user's state.
      if (!mounted || !widget.isAuthenticated()) return;
      widget.bookingController.applyLedger(
        dues: (led['dues'] as num?)?.toInt() ?? 0,
        held: (led['held'] as num?)?.toInt() ?? 0,
        depositPaid: (led['wallet_held'] as num?)?.toInt() ??
            (led['deposit_paid'] as num?)?.toInt() ??
            0,
      );
    } catch (_) {
      // Offline — the server stays the authority at order commit.
    }
  }

  void _selectTab(UserTab tab) {
    final changed = _tab != tab || !_mounted.contains(tab);
    setState(() {
      _tab = tab;
      _mounted.add(tab);
    });
    // The list may predate a just-placed order (recovery "Check Orders") or
    // a previous visit's cancellations/assignments.
    if (changed && tab == UserTab.orders && widget.isAuthenticated()) {
      widget.ordersController.load();
    }
  }

  void _select(int index) => _selectTab(UserTab.values[index]);

  void _login() {
    widget.onLoginRequested(context);
  }

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
  void _openWallet() => _selectTab(UserTab.wallet);

  /// Profile/Home → Addresses; guests go through register first and the gate
  /// re-checks live auth (never stranded on a 401 after the form).
  void _openAddresses() {
    openAddressesGated(
      context,
      isAuthed: widget.isAuthenticated,
      ensureAuth: widget.onLoginRequested,
      openAddresses: (ctx) => Navigator.of(ctx).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AddressScreen(controller: widget.addresses),
        ),
      ),
    );
  }

  /// BOOK NOW / detail BUY / reorder → checkout → confirmation → tab jump.
  Future<void> _openCheckout() async {
    final c = widget.bookingController;
    if (!c.canBook || c.isTanker) return;
    await showCheckoutSheet(
      context,
      controller: c,
      api: widget.api,
      razorpayKeyId: widget.razorpayKeyId,
      address: widget.addresses.resolve(),
      onChangeAddress: () {
        Navigator.of(context).pop();
        _openAddresses();
      },
      onDone: (result) {
        Navigator.of(context).pop();
        showOrderConfirm(
          context,
          result: result,
          onTrackOrder: () => _selectTab(UserTab.orders),
          onOpenSubscriptions: () => _selectTab(UserTab.subscriptions),
        );
      },
    );
  }

  /// One-tap repeat: refill lines from a past order, jump home, checkout.
  Future<void> _reorder(Order order) async {
    final c = widget.bookingController;
    c.setRefill(order.refillQty);
    c.setContainer(order.containerQty);
    _selectTab(UserTab.home);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _openCheckout();
  }

  /// Wallet → Returns: pick one of the saved delivery addresses (the returns
  /// feature stays free of address imports; the shell maps the result).
  Future<ReturnAddress?> _pickReturnAddress(BuildContext sheetContext) async {
    if (widget.addresses.items.isEmpty) {
      await Navigator.of(sheetContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AddressScreen(controller: widget.addresses),
        ),
      );
      if (!sheetContext.mounted || widget.addresses.items.isEmpty) {
        return null;
      }
    }
    final chosen = await showModalBottomSheet<AddressEntry>(
      context: sheetContext,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Pickup address',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final a in widget.addresses.items)
              ListTile(
                leading: const Icon(
                  Icons.location_on_outlined,
                  color: ShodashaTheme.teal,
                ),
                title: Text(a.label),
                subtitle: Text(a.addressLine),
                onTap: () => Navigator.of(ctx).pop(a),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return null;
    return ReturnAddress(
      id: chosen.id,
      label: '${chosen.label} · ${chosen.addressLine}',
    );
  }

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
        UserTab.home => HomeScreen(
            controller: widget.bookingController,
            api: widget.api,
            addresses: widget.addresses,
            ensureAuth: () => widget.onLoginRequested(context),
            onOpenAddresses: _openAddresses,
            onBuy: _openCheckout,
            onTrackOrder: () => _selectTab(UserTab.orders),
            onOpenSubscriptions: () => _selectTab(UserTab.subscriptions),
            razorpayKeyId: widget.razorpayKeyId,
          ),
        UserTab.orders => widget.isAuthenticated()
            ? OrdersScreen(
                controller: widget.ordersController,
                isAuthenticated: widget.isAuthenticated,
                onReorder: _reorder,
                onOpenPayments: _openPayments,
                onSupport: _openSupport,
              )
            : _GuestBody(
                icon: Icons.receipt_long_outlined,
                title: 'Orders',
                message: 'Sign in to see your orders.',
                onSignIn: _login,
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
            pickAddress: _pickReturnAddress,
          ),
        UserTab.profile => ProfileScreen(
            api: widget.api,
            isAuthenticated: widget.isAuthenticated(),
            controller: widget.profileController,
            onLoginRequired: _login,
            onLogout: widget.onLogout,
            onOpenAddresses: _openAddresses,
            onOpenPayments: _openPayments,
          ),
      };
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
