// VendorShell: 4-tab shell (Route · Earnings · Support · More) + drawer.
// Wave 1 honesty: 7 destinations mistapped outdoors; Customers/Stock/Sync-log
// live as Route sections + drawer entries (same screens, fewer tabs).
// Duty gates entry: off-duty vendors land on DutyScreen first.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart' show kSupportPhone;
import '../../core/theme.dart';
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

  @override
  State<VendorShell> createState() => _VendorShellState();
}

class _VendorShellState extends State<VendorShell>
    with WidgetsBindingObserver {
  int _tab = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

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
    final uri = Uri.parse('https://wa.me/919302190067');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // Duty gate: off-duty → duty screen (switch on to enter the shell).
    if (!widget.duty.onDuty &&
        widget.duty.state != DutyState.loading) {
      return DutyScreen(controller: widget.duty);
    }
    final pending = widget.sync.queue.length;
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Customers'),
                subtitle: const Text('Aaj ke grahak, khoj ke saath'),
                onTap: () {
                  Navigator.of(context).pop();
                  _push(CustomersScreen(
                      controller: widget.customers));
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Stock'),
                subtitle: const Text('Loading sheet: fulls/khaali'),
                onTap: () {
                  Navigator.of(context).pop();
                  _push(InventoryScreen(route: widget.route));
                },
              ),
              ListTile(
                leading: Badge(
                  isLabelVisible: pending > 0,
                  label: Text('$pending'),
                  child: const Icon(Icons.sync_outlined),
                ),
                title: const Text('Sync log'),
                subtitle: Text(pending > 0
                    ? '$pending baki — detail dekhein'
                    : 'Sab synced'),
                onTap: () {
                  Navigator.of(context).pop();
                  _push(SyncScreen(controller: widget.sync));
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Profile'),
                subtitle: const Text('Dukaan profile, bhasha, logout'),
                onTap: () {
                  Navigator.of(context).pop();
                  _push(ProfileScreen(
                    auth: widget.auth,
                    meLoader: widget.meLoader,
                    profileLoader: widget.profileLoader,
                    profileSaver: widget.profileSaver,
                  ));
                },
              ),
              ListTile(
                leading: const Icon(Icons.support_agent_outlined),
                title: Text('WhatsApp help ($kSupportPhone)'),
                onTap: () {
                  Navigator.of(context).pop();
                  _whatsapp();
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await widget.auth.logout();
                },
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Phase 5 §5.1: 30-day cap within 24h — warning only, the shift
          // continues (cap logout still needs a re-login, queue is kept).
          if (widget.auth.capExpiresSoon)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: ShodashaTheme.blueTint,
              child: Text(
                vendorStringsHi['capExpiring']!,
                style: const TextStyle(
                    color: ShodashaTheme.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                RouteScreen(
                  controller: widget.route,
                  onOpenStop: (s) => _openStop(context, s),
                  onOpenCustomers: () => _push(
                      CustomersScreen(controller: widget.customers)),
                  onOpenSync: () =>
                      _push(SyncScreen(controller: widget.sync)),
                  // 016 dashboard: money + ledger sections reuse tab controllers.
                  earnings: widget.earnings,
                  customers: widget.customers,
                ),
                EarningsScreen(controller: widget.earnings),
                SupportScreen(controller: widget.support),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          // 4th destination opens the drawer instead of a tab.
          if (i == 3) {
            _scaffoldKey.currentState?.openDrawer();
            return;
          }
          setState(() => _tab = i);
        },
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
              child: const Icon(Icons.menu_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.menu),
            ),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
