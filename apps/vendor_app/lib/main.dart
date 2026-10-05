// Shodasha Vendor app — composition root: theme + ApiClient + auth seams +
// feature controllers + AuthGate → VendorShell. Vendors must log in (no
// guest browse). Base URL via --dart-define=SHODASHA_API_BASE.
// Login is access-code-only (028): phone + admin-issued code, no OTP SDK.

import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/auth_impls.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_gate.dart';
import 'features/customers/customers_controller.dart';
import 'features/duty/duty_controller.dart';
import 'features/earnings/earnings_controller.dart';
import 'features/route/route_controller.dart';
import 'features/shell/vendor_shell.dart';
import 'features/stops/stops_controller.dart';
import 'features/support/support_controller.dart';
import 'features/sync/sync_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VendorApp());
}

class VendorApp extends StatefulWidget {
  const VendorApp({super.key});

  @override
  State<VendorApp> createState() => _VendorAppState();
}

class _VendorAppState extends State<VendorApp> {
  late final ApiClient _api;
  late final ApiClient _liveApi;
  late final AuthController _auth;
  late final DutyController _duty;
  late final RouteController _route;
  late final StopsController _stops;
  late final SyncController _sync;
  late final EarningsController _earnings;
  late final SupportController _support;
  late final CustomersController _customers;
  late final String _deviceId;

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    _deviceId = await loadOrCreateDeviceId();
    _api = ApiClient(deviceId: _deviceId);
    _auth = AuthController(
      api: ApiBackedAuthApi(_api),
      store: SecureSessionStore(),
      deviceId: _deviceId,
    );
    // Bearer tracks the session without rebuilding controllers after login.
    _liveApi = ApiClient(
      deviceId: _deviceId,
      accessTokenGetter: () => _auth.session?.accessToken,
      // 401/403 (revoked/suspended/expired): wipe locally, back to login.
      // forceLogout never calls the server, so this cannot loop.
      onUnauthorized: () => _auth.forceLogout(),
    );
    // Logout (manual or forced) also drops the offline outbox: a shared
    // device must never leak prior stops/cash into the next vendor's sync.
    _auth.onLogoutCleanup = () => _sync.clearAll();
    final liveApi = _liveApi;
    _duty = DutyController(api: liveApi);
    _route = RouteController(api: liveApi);
    _stops = StopsController(api: liveApi);
    _sync = SyncController(api: liveApi);
    _earnings = EarningsController(api: liveApi);
    _support = SupportController(api: liveApi);
    _customers = CustomersController(api: liveApi);
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _auth.dispose();
    _duty.dispose();
    _route.dispose();
    _stops.dispose();
    _sync.dispose();
    _earnings.dispose();
    _support.dispose();
    _customers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        theme: buildShodashaTheme(),
        home: const Scaffold(
            body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      title: 'Shodasha Vendor',
      debugShowCheckedModeBanner: false,
      theme: buildShodashaTheme(),
      home: AuthGate(
        controller: _auth,
        home: VendorShell(
          auth: _auth,
          duty: _duty,
          route: _route,
          stops: _stops,
          sync: _sync,
          earnings: _earnings,
          support: _support,
          customers: _customers,
          meLoader: () => _liveApi.me(),
          profileLoader: () => _liveApi.vendorProfile(),
          profileSaver: (fields) => _liveApi.saveVendorProfile(fields),
        ),
      ),
    );
  }
}
