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
import '../../core/theme.dart';
import '../../shared/ui/app_card.dart';
import '../../shared/ui/app_sheet.dart';
import '../../shared/ui/app_state_view.dart';
import '../addresses/address_screen.dart';
import '../auth/auth_controller.dart';
import '../booking/booking_controller.dart';
import '../booking/booking_sheet.dart';
import '../booking/quote_confirm.dart';
import '../home/customer_home_screen.dart';
import '../home/notifications_screen.dart';
import '../orders/orders_controller.dart';
import '../orders/my_orders_screen.dart';
import '../orders/tracking_screen.dart';
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
  bool _routeBusy = false;
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
    if (_tab == tab && tab != DonorTab.wallet) return;
    setState(() {
      _tab = tab;
      _mounted.add(tab);
      if (tab == DonorTab.wallet) _walletTick++;
    });
  }

  Future<void> _pushRoute(Widget page) async {
    if (_routeBusy || !mounted) return;
    _routeBusy = true;
    try {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
    } finally {
      _routeBusy = false;
    }
  }

  Future<void> _openAddresses() async {
    await _pushRoute(AddressScreen(controller: widget.addresses));
    if (mounted) await widget.addresses.load();
  }

  void _openSupport() {
    final delivered = [
      for (final order in widget.orders.allOrders)
        if (order.state == OrderState.delivered)
          SupportOrder(
            id: order.id,
            label:
                '#${order.id.length > 8 ? order.id.substring(0, 8) : order.id}'
                '${order.itemSummary.isEmpty ? '' : ' · ${order.itemSummary}'}',
            deliveredAt: order.createdAt,
          ),
    ];
    unawaited(_pushRoute(SupportScreen(api: widget.api, orders: delivered)));
  }

  void _openTracking(String orderId) {
    unawaited(
      _pushRoute(
        TrackingScreen(
          controller: widget.orders,
          orderId: orderId,
          onSupport: _openSupport,
        ),
      ),
    );
  }

  void _openNotifications() {
    unawaited(
      _pushRoute(
        DonorNotificationsScreen(
          api: widget.api,
          orders: widget.orders,
          onOpenOrder: _openTracking,
          onOpenSubscriptions: () {
            Navigator.of(context).pop();
            _selectTab(DonorTab.subscriptions);
          },
        ),
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

  void _openCart() {
    if (widget.booking.totalJars == 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Your cart is empty. Pick a can to start an order.'),
          ),
        );
      return;
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
    unawaited(_refreshLedger());
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
      onSignIn: () => unawaited(widget.auth.forceLogout()),
    );
  }

  Future<void> _openSearch() async {
    final picked = await showAppSheet<_ProductPick>(
      context: context,
      builder: (sheetContext) => _SearchSheet(
        booking: widget.booking,
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
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
        bottomNavigationBar: SafeArea(
          top: false,
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: NavigationBar(
                selectedIndex: _tab.index,
                onDestinationSelected: (i) => _selectTab(DonorTab.values[i]),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long_rounded),
                    label: 'Orders',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    selectedIcon: Icon(Icons.calendar_month_rounded),
                    label: 'Plans',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                    label: 'Wallet',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
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
      onOpenSupport: _openSupport,
      onOpenCart: _openCart,
      onSearch: _openSearch,
      onOrderProduct: _orderProduct,
    ),
    DonorTab.orders => DonorOrdersScreen(
      controller: widget.orders,
      onSupport: _openSupport,
      onStartOrder: _instantOrder,
    ),
    DonorTab.subscriptions => SubscriptionScreen(
      api: widget.api,
      onOpenWallet: () => _selectTab(DonorTab.wallet),
      onSignIn: () => unawaited(widget.auth.forceLogout()),
      onAddAddress: _openAddresses,
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
  const _SearchSheet({required this.booking, required this.onClose});

  final BookingController booking;
  final VoidCallback onClose;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.booking.rates == null && !widget.booking.ratesLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.booking.refreshRates();
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Search water',
      onClose: widget.onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Try “20L refill”',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ListenableBuilder(
            listenable: widget.booking,
            builder: (context, _) {
              final rates = widget.booking.rates;
              if (rates == null) {
                final error = widget.booking.ratesError;
                if (error != null) {
                  return AppStateView.error(
                    title: 'Search unavailable',
                    message: error,
                    onRetry: widget.booking.refreshRates,
                  );
                }
                return AppStateView.loading(
                  lines: 2,
                  message: 'Loading products',
                );
              }
              final q = _query.text.trim().toLowerCase();
              final items =
                  <({String title, String price, _ProductPick pick})>[
                        (
                          title: '20L refill can',
                          price: formatInr(rates.refillPaise),
                          pick: const _ProductPick(refill: 1, container: 0),
                        ),
                        (
                          title: '20L can + new jar',
                          price: formatInr(rates.containerPaise),
                          pick: const _ProductPick(refill: 0, container: 1),
                        ),
                      ]
                      .where(
                        (e) => q.isEmpty || e.title.toLowerCase().contains(q),
                      )
                      .toList();
              if (items.isEmpty) {
                return AppStateView.empty(
                  title: 'No matching can',
                  message: 'Try “refill” or “jar”.',
                  icon: Icons.search_off_rounded,
                );
              }
              return Column(
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        onTap: () => Navigator.of(context).pop(item.pick),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: ShodashaTheme.minTarget,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.water_drop_outlined,
                                color: ShodashaTheme.tealDeep,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: ShodashaTheme.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      item.price,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: ShodashaTheme.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: ShodashaTheme.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
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
        color: ShodashaTheme.solarTint,
        border: Border(bottom: BorderSide(color: ShodashaTheme.solar)),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 2, AppSpacing.sm, 2),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: ShodashaTheme.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text(
              'No internet — showing what was already loaded.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: ShodashaTheme.warning,
              ),
            ),
          ),
          TextButton(
            onPressed: retrying ? null : onRetry,
            style: TextButton.styleFrom(
              foregroundColor: ShodashaTheme.warning,
              minimumSize: const Size(48, ShodashaTheme.minTarget),
            ),
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
      color: ShodashaTheme.greenTint,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: const Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 18,
            color: ShodashaTheme.successDark,
          ),
          SizedBox(width: AppSpacing.sm),
          Text(
            'Back online.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ShodashaTheme.successDark,
            ),
          ),
        ],
      ),
    );
  }
}
