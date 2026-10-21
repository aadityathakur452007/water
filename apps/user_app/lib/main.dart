// Shodasha user app (032-user-app-replacement) — composition root.
//
// All slices live: AuthGate owns session restore; Home + checkout (S3),
// addresses (S4), Orders (S5), Subscriptions (S6), Wallet/returns (S7) and
// Profile/support (S8) share one ApiClient. Razorpay's publishable key comes
// from --dart-define (never hardcoded).
//
// Guest-browse contract (user-flows flow 1): prices stay visible without
// login; register gates only booking commit + account data.

import 'dart:async';

import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/auth_impls.dart';
import 'core/payment_config.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'features/addresses/address_screen.dart';
import 'features/addresses/selected_address_store.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_gate.dart';
import 'features/booking/booking_controller.dart';
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
  late final BookingController _booking;
  late final AddressController _addresses;
  late final SelectedAddressStore _selectedStore;
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
    // Catalog attaches when Home mounts (HttpCatalogApi); prices are
    // server-owned with no offline fallback (S3 money law).
    _booking = BookingController();
    _addresses = AddressController(api: _api);
    _selectedStore = SelectedAddressStore();
    // Persistence behind the live selection: restore once, then the
    // controller writes through on every select (011_port).
    unawaited(_selectedStore.load().then((_) {
      _addresses.bindSelection(_selectedStore);
    }));
    _orders = OrdersController(repo: ApiBackedOrdersRepository(_api));
    _profile = ProfileController(api: _api);
    // Session boundary: when the session ends (logout, expiry, 401) drop
    // every user-scoped controller so the next account can never see the
    // previous user's orders/addresses/identity/ledger. AuthGate unmounts
    // the shell at the same moment — this owner is the one that survives
    // the swap, so the reset lives here, not in the shell.
    _auth.addListener(_onAuthBoundaryChanged);
    if (mounted) setState(() => _ready = true);
  }

  bool _wasAuthenticated = false;

  void _onAuthBoundaryChanged() {
    final authed = _auth.isAuthenticated;
    if (authed == _wasAuthenticated) return;
    _wasAuthenticated = authed;
    if (authed) return;
    _booking.resetUserScoped();
    _addresses.reset();
    _orders.reset();
    _profile.reset();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthBoundaryChanged);
    _booking.dispose();
    _addresses.dispose();
    _selectedStore.dispose();
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
          bookingController: _booking,
          addresses: _addresses,
          ordersController: _orders,
          profileController: _profile,
          isAuthenticated: () => _auth.isAuthenticated,
          onLoginRequested: (ctx) => openRegister(ctx, _auth),
          onLogout: _auth.logout,
          razorpayKeyId: kRazorpayKeyId,
        ),
      ),
    );
  }
}
