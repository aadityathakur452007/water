// F5 — Bottom-nav shell: Home / Orders / Support / Profile (approved app map).
//
// Home hosts the F3 booking repeat machine; Orders hosts F4's list/detail/
// tracking/bill; Support (new) = WhatsApp + FAQ + complaints; Profile (new)
// = identity + ledger + returns + language + logout. No sheet/tab may look
// logged-out mid-session (States.md auth states): guest + un-authed tab
// actions route through [AuthGate] via the commit-gate callback.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../addresses/address_screen.dart';
import '../auth/first_run_screen.dart';
import '../booking/booking_controller.dart';
import '../booking/booking_sheet.dart';
import '../booking/home_screen.dart';
import '../booking/quote_confirm.dart';
import '../orders/orders_controller.dart';
import '../orders/orders_screen.dart';
import '../profile/profile_screen.dart';
import '../support/support_screen.dart';
import '../../core/theme.dart';

/// Tab indices are stable identifiers (deep links + tests).
enum UserTab { home, orders, support, profile }

class UserShell extends StatefulWidget {
  const UserShell({
    super.key,
    required this.bookingController,
    required this.ordersController,
    required this.isAuthenticated,
    this.api,
    this.addresses,
    this.razorpayKeyId = '',
    this.onOpenAddresses,
    this.onOpenSubscriptions,
    this.onLogout,
  });

  final BookingController bookingController;
  final OrdersController ordersController;

  /// Live auth check for tab-level gates (profile requires login content).
  final bool Function() isAuthenticated;

  /// Shared API + address source for home/checkout (null = guest stub).
  final ApiClient? api;
  final AddressController? addresses;

  /// Publishable Razorpay test key (--dart-define RAZORPAY_KEY_ID).
  final String razorpayKeyId;

  /// Profile → Addresses / Subscriptions routes + logout (main.dart wiring).
  final VoidCallback? onOpenAddresses;
  final VoidCallback? onOpenSubscriptions;
  final VoidCallback? onLogout;

  @override
  State<UserShell> createState() => _UserShellState();
}

class _UserShellState extends State<UserShell> {
  UserTab _tab = UserTab.home;

  @override
  void initState() {
    super.initState();
    widget.addresses?.addListener(_onAddresses);
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerFirstRun());
  }

  @override
  void dispose() {
    widget.addresses?.removeListener(_onAddresses);
    super.dispose();
  }

  void _onAddresses() {
    if (mounted) setState(() {});
  }

  /// First-run: zero addresses → permission + address-pin sheet (once).
  Future<void> _offerFirstRun() async {
    final addresses = widget.addresses;
    if (addresses == null || !mounted) return;
    if (addresses.status == AddrStatus.initial) {
      await addresses.load();
      if (!mounted) return;
    }
    await maybeOfferFirstRun(
      context,
      addressCount: addresses.items.length,
      onAddAddress: () => widget.onOpenAddresses?.call(),
    );
  }

  /// Delivery address: selected (when still saved) → default → first.
  AddressEntry? get _defaultAddress => widget.addresses?.resolve();

  /// One-tap repeat: refill the booking lines from a past order, jump
  /// home, and open checkout (known mix only — card hides otherwise).
  Future<void> _reorder(Order order) async {
    final c = widget.bookingController;
    c.setRefill(order.refillQty);
    c.setContainer(order.containerQty);
    if (!mounted) return;
    setState(() => _tab = UserTab.home);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _openCheckout();
  }

  /// BOOK NOW / detail BUY → checkout → confirmation → tab jump.
  Future<void> _openCheckout() async {
    final api = widget.api;
    if (api == null) return;
    final c = widget.bookingController;
    if (!c.canBook || c.isTanker) return;
    await showCheckoutSheet(
      context,
      controller: c,
      api: api,
      razorpayKeyId: widget.razorpayKeyId,
      address: _defaultAddress,
      onChangeAddress: () {
        Navigator.of(context).pop();
        widget.onOpenAddresses?.call();
      },
      onDone: (result) {
        Navigator.of(context).pop();
        showOrderConfirm(
          context,
          result: result,
          onTrackOrder: () {
            if (result.isSubscription) {
              widget.onOpenSubscriptions?.call();
            } else {
              setState(() => _tab = UserTab.orders);
            }
          },
          onOpenSubscriptions: () =>
              widget.onOpenSubscriptions?.call(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <UserTab, Widget>{
      UserTab.home: HomeScreen(
        controller: widget.bookingController,
        addresses: widget.addresses,
        onOpenAddresses: widget.onOpenAddresses,
        onBuy: _openCheckout,
      ),
      UserTab.orders: OrdersScreen(
        controller: widget.ordersController,
        onReorder: _reorder,
      ),
      UserTab.support: const SupportScreen(),
      UserTab.profile: ProfileScreen(
        isAuthenticated: widget.isAuthenticated(),
        onOpenAddresses: widget.onOpenAddresses,
        onOpenSubscriptions: widget.onOpenSubscriptions,
        onLogout: widget.onLogout,
      ),
    };
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      body: IndexedStack(
        index: _tab.index,
        children: UserTab.values.map((t) => pages[t]!).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (i) => setState(() => _tab = UserTab.values[i]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent),
            label: 'Support',
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
