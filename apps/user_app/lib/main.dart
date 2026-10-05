// Shodasha user app — F5 wiring: theme + API client + auth seams + 4-tab
// shell (Home/Orders/Support/Profile) + addresses/subscriptions routes.
//
// Guest-browse contract (user-flows flow 1): prices stay visible without
// login; register gates only booking commit + profile data (AuthGate routes
// the shell; ProfileScreen shows the login CTA when un-authed).

import 'dart:async';

import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/auth_impls.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'features/addresses/address_screen.dart';
import 'features/addresses/selected_address_store.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/name_number_screen.dart';
import 'features/booking/booking_controller.dart';
import 'features/orders/orders_controller.dart';
import 'features/profile/profile_screen.dart';
import 'features/shell/user_shell.dart';
import 'features/subscriptions/subscription_screen.dart';

/// Publishable Razorpay test key (public by design — the secret stays
/// server-side in workers/api/.env). Empty = UPI gateway disabled with
/// an honest message; COD keeps working.
const String kRazorpayKeyId = String.fromEnvironment(
  'RAZORPAY_KEY_ID',
  defaultValue: '',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShodashaApp());
}

/// Composition root: one ApiClient + AuthController + feature controllers
/// shared by the shell and pushed routes.
class ShodashaApp extends StatefulWidget {
  const ShodashaApp({super.key});

  @override
  State<ShodashaApp> createState() => _ShodashaAppState();
}

class _ShodashaAppState extends State<ShodashaApp> {
  late final ApiClient _api;
  late final AuthController _auth;
  late final BookingController _booking;
  late final OrdersController _orders;
  late final AddressController _addresses;
  late final SelectedAddressStore _selectedStore;
  late final SubscriptionController _subs;
  late final ProfileController _profile;

  late final String _deviceId;

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  /// Phase 4 §4.3–§4.4 (mirrors the vendor `_boot`): stable per-install
  /// device id (fraud graph, SEC-F01) instead of `'pending-device'`; Bearer
  /// tracks the session without rebuilding controllers after login (the
  /// closures read `_auth` lazily — the first authed call happens long
  /// after boot, so the late field is assigned); 401/403 wipes locally
  /// back to login via [AuthController.forceLogout] (never loops: the hook
  /// never calls the server); catalog reads live `GET /catalog` with the
  /// hardcoded fallback kept for offline honesty.
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
    _booking = BookingController(
      catalog: CachingCatalogApi(HttpCatalogApi(_api)),
    );
    _orders = OrdersController(repo: ApiBackedOrdersRepository(_api));
    _addresses = AddressController(api: _api);
    _selectedStore = SelectedAddressStore();
    // Persistence behind the live selection: restore once, then the
    // controller writes through on every select (011_port).
    unawaited(_selectedStore.load().then((_) {
      _addresses.bindSelection(_selectedStore);
    }));
    _subs = SubscriptionController(api: _api);
    _profile = ProfileController(api: _api);
    // Live rates on home init (best-effort; hardcoded fallback stays).
    unawaited(_booking.refreshRates());
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _booking.dispose();
    _orders.dispose();
    _addresses.dispose();
    _selectedStore.dispose();
    _subs.dispose();
    _profile.dispose();
    _auth.dispose();
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
      title: 'Shodasha',
      debugShowCheckedModeBanner: false,
      theme: buildShodashaTheme(),
      home: AuthGate(
        controller: _auth,
        home: _ShellPage(app: this),
        // Login screen's guest action returns straight into the shell
        // (prices never walled — flow 1).
      ),
    );
  }
}

/// Shell page: hosts UserShell + pushes Addresses/Subscriptions from Profile.
class _ShellPage extends StatelessWidget {
  const _ShellPage({required this.app});

  final _ShodashaAppState app;

  void _openAddresses(BuildContext context) {
    openAddressesGated(
      context,
      isAuthed: () => app._auth.isAuthenticated,
      openLogin: (ctx) => Navigator.of(ctx).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _LoginGatePage(auth: app._auth),
        ),
      ),
      openAddresses: (ctx) => _pushAddressScreen(ctx),
    );
  }

  void _pushAddressScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddressScreen(controller: app._addresses),
      ),
    );
  }

  void _openSubscriptions(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubscriptionScreen(controller: app._subs),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authed = app._auth.isAuthenticated;
    return UserShell(
      bookingController: app._booking,
      ordersController: app._orders,
      isAuthenticated: () => authed,
      api: app._api,
      addresses: app._addresses,
      razorpayKeyId: kRazorpayKeyId,
      onOpenAddresses: () => _openAddresses(context),
      onOpenSubscriptions: () => _openSubscriptions(context),
      onLogout: () async {
        await app._auth.logout();
      },
    );
  }
}

/// Address entry gate (composition root): authed users go straight to
/// Addresses; guests go through login first and land on Addresses after
/// register (the gate re-checks live state instead of trusting a route
/// result). Never strands a guest on a server 401 after filling the 3-step
/// form.
Future<void> openAddressesGated(
  BuildContext context, {
  required bool Function() isAuthed,
  required Future<void> Function(BuildContext context) openLogin,
  required void Function(BuildContext context) openAddresses,
}) async {
  if (!isAuthed()) {
    await openLogin(context);
    if (!context.mounted) return;
    if (!isAuthed()) return;
  }
  if (!context.mounted) return;
  openAddresses(context);
}

/// Login page for the address gate: no guest-browse escape hatch (that would
/// loop back into the same gate); the back button cancels the entry.
/// Register/demo logins authenticate without pushing OTP — the listener
/// closes the gate then (the `isCurrent` check keeps pop drivers from
/// racing).
class _LoginGatePage extends StatefulWidget {
  const _LoginGatePage({required this.auth});

  final AuthController auth;

  @override
  State<_LoginGatePage> createState() => _LoginGatePageState();
}

class _LoginGatePageState extends State<_LoginGatePage> {
  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onAuth);
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    if (!widget.auth.isAuthenticated || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login karein')),
      body: NameNumberScreen(controller: widget.auth),
    );
  }
}
