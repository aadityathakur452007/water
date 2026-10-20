// Shodasha user app (032-user-app-replacement) — composition root.
//
// S1: device id + ApiClient + AuthController + 5-tab shell skeleton.
// S2/S5/S7/S8: AuthGate owns session restore; Orders / Wallet / Profile
// tabs are live against the shared transport. Home (S3) and Subscriptions
// (S6) attach in the next wiring pass.
//
// Guest-browse contract (user-flows flow 1): prices stay visible without
// login; register gates only booking commit + profile data.

import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/auth_impls.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_gate.dart';
import 'features/orders/orders_controller.dart';
import 'features/profile/profile_controller.dart';
import 'features/shell/user_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShodashaApp());
}

/// Composition root: one ApiClient + controllers shared by the shell and
/// pushed routes.
class ShodashaApp extends StatefulWidget {
  const ShodashaApp({super.key});

  @override
  State<ShodashaApp> createState() => _ShodashaAppState();
}

class _ShodashaAppState extends State<ShodashaApp> {
  late final ApiClient _api;
  late final AuthController _auth;
  late final OrdersController _orders;
  late final ProfileController _profile;
  late final String _deviceId;

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  /// Stable per-install device id (fraud graph, SEC-F01); Bearer tracks the
  /// session without rebuilding controllers after login (the closures read
  /// `_auth` lazily — the first authed call happens long after boot, so the
  /// late field is assigned); 401/403 wipes locally back to guest via
  /// [AuthController.forceLogout] (never loops: the hook never calls the
  /// server). Session restore is owned by [AuthGate] (its splash).
  Future<void> _boot() async {
    _deviceId = await loadOrCreateDeviceId();
    _api = ApiClient(
      deviceId: _deviceId,
      accessTokenGetter: () => _auth.session?.accessToken,
      onUnauthorized: () => _auth.forceLogout(),
    );
    _auth = AuthController(
      api: ApiBackedAuthApi(_api),
      store: SecureSessionStore(),
      deviceId: _deviceId,
    );
    _orders = OrdersController(repo: ApiBackedOrdersRepository(_api));
    _profile = ProfileController(api: _api);
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _orders.dispose();
    _profile.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        theme: buildShodashaTheme(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      title: 'Shodasha',
      debugShowCheckedModeBanner: false,
      theme: buildShodashaTheme(),
      home: AuthGate(
        controller: _auth,
        home: UserShell(
          api: _api,
          authListenable: _auth,
          ordersController: _orders,
          profileController: _profile,
          isAuthenticated: () => _auth.isAuthenticated,
          onLoginRequested: (ctx) => openRegister(ctx, _auth),
          onLogout: _auth.logout,
        ),
      ),
    );
  }
}
