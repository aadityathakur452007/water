// VendorShell: 7-tab shell (Route · Customers · Stock · Sync · Earnings ·
// Support · Profile). Duty gates entry: off-duty vendors land on DutyScreen.

import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
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

class _VendorShellState extends State<VendorShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.duty.addListener(_onDuty);
    widget.sync.addListener(_onSync);
    widget.duty.load();
    widget.sync.load();
  }

  void _onDuty() {
    if (mounted) setState(() {});
  }

  void _onSync() {
    widget.route.pendingSync = widget.sync.queue.length;
  }

  @override
  void dispose() {
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
        ),
      ),
    );
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
      body: IndexedStack(
        index: _tab,
        children: [
          RouteScreen(
            controller: widget.route,
            onOpenStop: (s) => _openStop(context, s),
          ),
          CustomersScreen(controller: widget.customers),
          InventoryScreen(route: widget.route),
          SyncScreen(controller: widget.sync),
          EarningsScreen(controller: widget.earnings),
          SupportScreen(controller: widget.support),
          ProfileScreen(
            auth: widget.auth,
            meLoader: widget.meLoader,
            profileLoader: widget.profileLoader,
            profileSaver: widget.profileSaver,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Route',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Customers',
          ),
          const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.sync_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.sync),
            ),
            label: 'Sync',
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
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
