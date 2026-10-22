// Donor five-tab shell: Home / My Orders / Subscriptions / Wallet / Profile.
//
// This is the only file that composes the donor screens with the proven 032
// controllers. Checkout, address management, tracking, bills, returns and
// subscription actions stay on the same server-backed flows as the 032 app;
// the donor visuals sit on top.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/constants/app_constants.dart';
import '../../core/money.dart';
import '../addresses/address_screen.dart';
import '../auth/auth_controller.dart';
import '../booking/booking_controller.dart';
import '../booking/booking_sheet.dart';
import '../booking/quote_confirm.dart';
import '../home/customer_home_screen.dart';
import '../home/notifications_screen.dart';
import '../orders/orders_controller.dart';
import '../orders/my_orders_screen.dart';
import '../profile/donor_profile_screen.dart';
import '../profile/profile_controller.dart';
import '../returns/return_sheet.dart';
import '../subscriptions/subscription_screen.dart';
import '../support/support_screen.dart';
import '../wallet/donor_wallet_screen.dart';

enum DonorTab { home, orders, subscriptions, wallet, profile }

class DonorShell extends StatefulWidget {
  const DonorShell({
    super.key,
    required this.api,
    required this.auth,
    required this.booking,
    required this.addresses,
    required this.orders,
    required this.profile,
    this.razorpayKeyId = '',
  });

  final ApiClient api;
  final AuthController auth;
  final BookingController booking;
  final AddressController addresses;
  final OrdersController orders;
  final ProfileController profile;
  final String razorpayKeyId;

  @override
  State<DonorShell> createState() => _DonorShellState();
}

class _DonorShellState extends State<DonorShell> {
  static const double _maxWidth = 560;

  DonorTab _tab = DonorTab.home;
  int _walletTick = 0;
  final Set<DonorTab> _mounted = {DonorTab.home};

  bool _wasOffline = false;
  bool _showRestored = false;
  bool _retrying = false;
  Timer? _restoredTimer;

  @override
  void initState() {
    super.initState();
    _wasOffline = widget.api.offline.value;
    widget.api.offline.addListener(_onOffline);
    if (widget.addresses.status == AddrStatus.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.addresses.load();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLedger());
  }

  @override
  void dispose() {
    widget.api.offline.removeListener(_onOffline);
    _restoredTimer?.cancel();
    super.dispose();
  }

  void _onOffline() {
    if (!mounted) return;
    final offline = widget.api.offline.value;
    if (offline) {
      _restoredTimer?.cancel();
      setState(() => _showRestored = false);
    } else if (_wasOffline) {
      setState(() => _showRestored = true);
      _restoredTimer?.cancel();
      _restoredTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showRestored = false);
      });
    }
    _wasOffline = offline;
  }

  Future<void> _retryOffline() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.api.catalog();
    } catch (_) {
      // Banner stays; each screen keeps its own retry.
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _refreshLedger() async {
    if (!mounted || !widget.auth.isAuthenticated) return;
    try {
      final led = await widget.api.ledgerMe();
      if (!mounted || !widget.auth.isAuthenticated) return;
      widget.booking.applyLedger(
        dues: (led['dues'] as num?)?.toInt() ?? 0,
        held: (led['held'] as num?)?.toInt() ?? 0,
        depositPaid:
            (led['wallet_held'] as num?)?.toInt() ??
            (led['deposit_paid'] as num?)?.toInt() ??
            0,
      );
    } catch (_) {
      // Server stays the authority at order commit.
    }
  }

  void _selectTab(DonorTab tab) {
    setState(() {
      _tab = tab;
      _mounted.add(tab);
      if (tab == DonorTab.wallet) _walletTick++;
    });
    if (tab == DonorTab.orders || tab == DonorTab.profile) {
      widget.orders.load();
    }
    if (tab == DonorTab.wallet) _refreshLedger();
  }

  void _openAddresses() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AddressScreen(controller: widget.addresses),
      ),
    );
  }

  void _openSupport() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => SupportScreen(api: widget.api)),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            DonorNotificationsScreen(api: widget.api, orders: widget.orders),
      ),
    );
  }

  void _instantOrder() {
    if (widget.booking.totalJars == 0) {
      widget.booking.setRefill(1);
      widget.booking.setContainer(0);
    }
    _openCheckout();
  }

  Future<void> _orderProduct({
    required int refill,
    required int container,
  }) async {
    widget.booking.setRefill(refill);
    widget.booking.setContainer(container);
    await _openCheckout();
  }

  Future<void> _openCheckout() async {
    final c = widget.booking;
    if (!c.canBook || c.isTanker) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one 20L jar.')),
      );
      return;
    }
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
        widget.orders.load();
        showOrderConfirm(
          context,
          result: result,
          onTrackOrder: () => _selectTab(DonorTab.orders),
          onOpenSubscriptions: () => _selectTab(DonorTab.subscriptions),
        );
        _refreshLedger();
      },
    );
  }

  Future<void> _openSearch() async {
    final picked = await showModalBottomSheet<_ProductPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SearchSheet(booking: widget.booking),
    );
    if (picked == null || !mounted) return;
    await _orderProduct(refill: picked.refill, container: picked.container);
  }

  Future<ReturnAddress?> _pickReturnAddress(BuildContext sheetContext) async {
    if (widget.addresses.items.isEmpty) {
      await Navigator.of(sheetContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AddressScreen(controller: widget.addresses),
        ),
      );
      if (!sheetContext.mounted || widget.addresses.items.isEmpty) return null;
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
                  color: AppColors.primary,
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
    return PopScope(
      canPop: _tab == DonorTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _tab == DonorTab.home) return;
        _selectTab(DonorTab.home);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: Column(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.api.offline,
                    builder: (_, offline, _) => offline
                        ? _OfflineStrip(
                            retrying: _retrying,
                            onRetry: _retryOffline,
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (_showRestored) const _RestoredStrip(),
                  Expanded(child: _tabs()),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: ColoredBox(
          color: AppColors.surface,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: BottomNavigationBar(
                currentIndex: _tab.index,
                onTap: (i) => _selectTab(DonorTab.values[i]),
                type: BottomNavigationBarType.fixed,
                backgroundColor: AppColors.surface,
                selectedItemColor: AppColors.primary,
                unselectedItemColor: AppColors.textSecondary,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
                unselectedLabelStyle: const TextStyle(fontSize: 10),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.receipt_long_outlined),
                    activeIcon: Icon(Icons.receipt_long_rounded),
                    label: 'My Orders',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.calendar_month_outlined),
                    activeIcon: Icon(Icons.calendar_month_rounded),
                    label: 'Subscriptions',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    activeIcon: Icon(Icons.account_balance_wallet_rounded),
                    label: 'Wallet',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline),
                    activeIcon: Icon(Icons.person_rounded),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabs() => IndexedStack(
    index: _tab.index,
    children: [
      for (final tab in DonorTab.values)
        _mounted.contains(tab) ? _bodyFor(tab) : const SizedBox.shrink(),
    ],
  );

  Widget _bodyFor(DonorTab tab) => switch (tab) {
    DonorTab.home => DonorHomeTab(
      api: widget.api,
      booking: widget.booking,
      addresses: widget.addresses,
      onInstantOrder: _instantOrder,
      onSubscribe: () => _selectTab(DonorTab.subscriptions),
      onOpenAddresses: _openAddresses,
      onOpenNotifications: _openNotifications,
      onOpenProfile: () => _selectTab(DonorTab.profile),
      onOpenCart: _instantOrder,
      onSearch: _openSearch,
      onOrderProduct: _orderProduct,
    ),
    DonorTab.orders => DonorOrdersScreen(
      controller: widget.orders,
      onSupport: _openSupport,
    ),
    DonorTab.subscriptions => SubscriptionScreen(
      api: widget.api,
      onOpenWallet: () => _selectTab(DonorTab.wallet),
    ),
    DonorTab.wallet => DonorWalletScreen(
      api: widget.api,
      onOpenSubscriptions: () => _selectTab(DonorTab.subscriptions),
      pickAddress: _pickReturnAddress,
      refreshTick: _walletTick,
    ),
    DonorTab.profile => ListenableBuilder(
      listenable: widget.orders,
      builder: (_, _) => DonorProfileScreen(
        auth: widget.auth,
        controller: widget.profile,
        addressController: widget.addresses,
        orderCount: widget.orders.totalCount,
        onOpenWallet: () => _selectTab(DonorTab.wallet),
        onOpenNotifications: _openNotifications,
        onOpenSupport: _openSupport,
        onOpenSubscriptions: () => _selectTab(DonorTab.subscriptions),
      ),
    ),
  };
}

class _ProductPick {
  const _ProductPick({required this.refill, required this.container});

  final int refill;
  final int container;
}

/// Search over the two real catalog SKUs. The donor search bar was decorative;
/// this one returns a real selection and then opens the normal checkout.
class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.booking});

  final BookingController booking;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Search water',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _query,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Try “20L refill”',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 14),
          ListenableBuilder(
            listenable: widget.booking,
            builder: (context, _) {
              final rates = widget.booking.rates;
              if (rates == null) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final q = _query.text.trim().toLowerCase();
              final items =
                  <({String title, String price, _ProductPick pick})>[
                        (
                          title: '20L Refill Water Can',
                          price: formatInr(rates.refillPaise),
                          pick: const _ProductPick(refill: 1, container: 0),
                        ),
                        (
                          title: '20L Water Can + New Jar',
                          price: formatInr(rates.containerPaise),
                          pick: const _ProductPick(refill: 0, container: 1),
                        ),
                      ]
                      .where(
                        (e) => q.isEmpty || e.title.toLowerCase().contains(q),
                      )
                      .toList();
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'No matching can. Try “refill” or “jar”.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              return Column(
                children: [
                  for (final item in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.water_drop,
                        color: AppColors.primary,
                      ),
                      title: Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(item.price),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).pop(item.pick),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip({required this.retrying, required this.onRetry});

  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: AppColors.error,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'No internet — showing what was already loaded.',
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: retrying ? null : onRetry,
            child: retrying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _RestoredStrip extends StatelessWidget {
  const _RestoredStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFDCFCE7),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF15803D)),
          SizedBox(width: 8),
          Text(
            'Back online.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF15803D),
            ),
          ),
        ],
      ),
    );
  }
}
