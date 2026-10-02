// Shodasha Vendor app — composition root: theme + ApiClient + auth seams +
// feature controllers + AuthGate → VendorShell. Vendors must log in (no
// guest browse). Base URL via --dart-define=SHODASHA_API_BASE.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/auth_impls.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_gate.dart';
import 'features/duty/duty_controller.dart';
import 'features/earnings/earnings_controller.dart';
import 'features/route/route_controller.dart';
import 'features/shell/vendor_shell.dart';
import 'features/stops/stops_controller.dart';
import 'features/support/support_controller.dart';
import 'features/sync/sync_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fail-soft until the vendor google-services.json lands (user manual step):
  // login screen still renders; OTP send surfaces the SMS error path.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[vendor] Firebase init deferred: $e');
  }
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
      verifier: FirebasePhoneVerifier(),
      store: SecureSessionStore(),
      deviceId: _deviceId,
    );
    // Bearer tracks the session without rebuilding controllers after login.
    _liveApi = ApiClient(
      deviceId: _deviceId,
      accessTokenGetter: () => _auth.session?.accessToken,
    );
    final liveApi = _liveApi;
    _duty = DutyController(api: liveApi);
    _route = RouteController(api: liveApi);
    _stops = StopsController(api: liveApi);
    _sync = SyncController(api: liveApi);
    _earnings = EarningsController(api: liveApi);
    _support = SupportController(api: liveApi);
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
          meLoader: () => _liveApi.me(),
        ),
      ),
    );
  }
}
