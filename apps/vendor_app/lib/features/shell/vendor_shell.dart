// VendorShell: 4-tab shell (Route · Earnings · Support · More).
// ADR-160: Retired side drawer (DEF-05); Tab 4 renders dedicated MoreHubScreen.
// Replaced blocking full-screen duty lockout with soft sticky banner (DEF-07).

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart' show kSupportPhone, ApiClient;
import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import '../auth/auth_controller.dart';
import '../auth/vendor_strings.dart';
import '../customers/customers_controller.dart';
import '../customers/customers_screen.dart';
import '../duty/duty_controller.dart';
import '../duty/duty_screen.dart';
import '../earnings/earnings_controller.dart';
import '../earnings/earnings_screen.dart';
import '../inventory/inventory_screen.dart';
import '../profile/profile_screen.dart';
import '../route/route_controller.dart';
import '../route/route_screen.dart';
import '../stops/stop_detail_screen.dart';
import '../stops/stops_controller.dart';
import '../support/support_controller.dart';
import '../support/support_screen.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_screen.dart';
import 'more_hub_screen.dart';

class VendorShell extends StatefulWidget {
  const VendorShell({
    super.key,
    required this.auth,
    required this.duty,
    required this.route,
    required this.stops,
    required this.sync,
    required this.earnings,
    required this.support,
    required this.customers,
    required this.meLoader,
    this.profileLoader,
    this.profileSaver,
    this.api,
  });

  final AuthController auth;
  final DutyController duty;
  final RouteController route;
  final StopsController stops;
  final SyncController sync;
  final EarningsController earnings;
  final SupportController support;
  final CustomersController customers;
  final Future<Map<String, dynamic>> Function() meLoader;
  final Future<Map<String, dynamic>> Function()? profileLoader;
  final Future<Map<String, dynamic>> Function(Map<String, String> fields)?
      profileSaver;
  final ApiClient? api;

  @override
  State<VendorShell> createState() => _VendorShellState();
}

class _VendorShellState extends State<VendorShell>
    with WidgetsBindingObserver {
  int _tab = 0;
  final Set<int> _mounted = {0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.auth.addListener(_onAuth);
    widget.duty.addListener(_onDuty);
    widget.sync.addListener(_onSync);
    widget.duty.load();
    widget.sync.load();
    _syncDiscovery();
  }

  void _onAuth() {
    if (mounted) setState(() {});
  }

  void _onDuty() {
    if (mounted) setState(() {});
    _syncDiscovery();
  }

  /// Phase 5 §5.4: discovery poll runs on-duty only (foreground).
  /// Off-duty, background, and dispose all stop it — no silent traffic.
  void _syncDiscovery() {
    if (widget.duty.onDuty) {
      widget.route.startDiscovery();
    } else {
      widget.route.stopDiscovery();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncDiscovery();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      widget.route.stopDiscovery();
    }
  }

  void _onSync() {
    widget.route.pendingSync = widget.sync.queue.length;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.route.stopDiscovery();
    widget.auth.removeListener(_onAuth);
    widget.duty.removeListener(_onDuty);
    widget.sync.removeListener(_onSync);
    super.dispose();
  }

  void _selectTab(int i) {
    setState(() {
      _mounted.add(i);
      _tab = i;
    });
  }

  void _openStop(BuildContext context, RouteStop stop) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StopDetailScreen(
          controller: widget.stops,
          stopId: stop.id,
          stopLabel: 'Stop ${stop.seq}: ${stop.customerName}',
          outbox: widget.sync,
        ),
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Future<void> _whatsapp() async {
    final digits = kSupportPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$digits');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _bodyFor(int index, bool isOffDuty, int pending) {
    if (!_mounted.contains(index)) return const SizedBox.shrink();
    return switch (index) {
      0 => isOffDuty
          ? _OffDutyRouteLock(
              onGoOnDuty: () => widget.duty.setDuty(true),
              onOpenEarnings: () => _selectTab(1),
            )
          : RouteScreen(
              controller: widget.route,
              api: widget.api,
              onOpenStop: (s) => _openStop(context, s),
              onOpenCustomers: () =>
                  _push(CustomersScreen(controller: widget.customers)),
              onOpenSync: () => _push(SyncScreen(controller: widget.sync)),
              earnings: widget.earnings,
              customers: widget.customers,
            ),
      1 => EarningsScreen(controller: widget.earnings),
      2 => SupportScreen(controller: widget.support),
      3 => MoreHubScreen(
          onOpenCustomers: () =>
              _push(CustomersScreen(controller: widget.customers)),
          onOpenStock: () => _push(InventoryScreen(route: widget.route)),
          onOpenSync: () => _push(SyncScreen(controller: widget.sync)),
          onOpenDuty: () => _push(DutyScreen(controller: widget.duty)),
          onOpenProfile: () => _push(ProfileScreen(
            auth: widget.auth,
            meLoader: widget.meLoader,
            profileLoader: widget.profileLoader,
            profileSaver: widget.profileSaver,
            api: widget.api,
          )),
          onWhatsApp: _whatsapp,
          onLogout: () async {
            await widget.auth.logout();
          },
          pendingSyncCount: pending,
          onDuty: widget.duty.onDuty,
        ),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.sync.queue.length;
    final isOffDuty =
        !widget.duty.onDuty && widget.duty.state != DutyState.loading;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // DEF-07: Soft sticky duty banner replaces full-screen lockout
            if (isOffDuty)
              _OffDutyBanner(
                loading: widget.duty.state == DutyState.loading,
                onGoOnDuty: () => widget.duty.setDuty(true),
                onOpenDutyScreen: () =>
                    _push(DutyScreen(controller: widget.duty)),
              ),
            // Phase 5 §5.1: 30-day cap warning
            if (widget.auth.capExpiresSoon)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: ShodashaTheme.blueTint,
                child: Text(
                  vendorStringsHi['capExpiring']!,
                  style: const TextStyle(
                    color: ShodashaTheme.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _bodyFor(0, isOffDuty, pending),
                  _bodyFor(1, isOffDuty, pending),
                  _bodyFor(2, isOffDuty, pending),
                  _bodyFor(3, isOffDuty, pending),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _selectTab,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Route',
          ),
          const NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments),
            label: 'Earnings',
          ),
          const NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent),
            label: 'Support',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.grid_view_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.grid_view_rounded),
            ),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _OffDutyBanner extends StatelessWidget {
  const _OffDutyBanner({
    required this.loading,
    required this.onGoOnDuty,
    required this.onOpenDutyScreen,
  });

  final bool loading;
  final VoidCallback onGoOnDuty;
  final VoidCallback onOpenDutyScreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: ShodashaTheme.amberTint,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.pause_circle_outline,
            size: 20,
            color: ShodashaTheme.ink,
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Currently Off Duty (छुट्टी पर हैं)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
                Text(
                  'Turn On Duty to receive delivery stops',
                  style: TextStyle(
                    fontSize: 11,
                    color: ShodashaTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(
            onPressed: loading ? null : onGoOnDuty,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              minimumSize: const Size(60, 36),
              backgroundColor: ShodashaTheme.ink,
              foregroundColor: ShodashaTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ShodashaTheme.surface,
                    ),
                  )
                : const Text(
                    'Go On Duty',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }
}

class _OffDutyRouteLock extends StatelessWidget {
  const _OffDutyRouteLock({
    required this.onGoOnDuty,
    required this.onOpenEarnings,
  });

  final VoidCallback onGoOnDuty;
  final VoidCallback onOpenEarnings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: ShodashaTheme.amberTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.pause_circle_filled_rounded,
                size: 36,
                color: ShodashaTheme.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'You are currently Off Duty',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ShodashaTheme.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Delivery stops are locked while off duty.\nEarnings and profile remain accessible.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: ShodashaTheme.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Go On Duty (ड्यूटी शुरू करें)',
              kind: AppButtonKind.primary,
              onPressed: onGoOnDuty,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'View Earnings (कमाई देखें)',
              kind: AppButtonKind.secondary,
              onPressed: onOpenEarnings,
            ),
          ],
        ),
      ),
    );
  }
}
