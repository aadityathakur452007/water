// Shodasha donor-parity customer app — composition root.
//
// One ApiClient + the proven 032 controllers are shared by the donor UI. Auth
// is mobile + password (034); legacy phone-code sign-in is retired. There is no guest-browse
// path in this clone. Razorpay's publishable key still comes from --dart-define
// and is never hardcoded.

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
import 'features/shell/donor_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShodashaDonorApp());
}

class ShodashaDonorApp extends StatefulWidget {
  const ShodashaDonorApp({super.key});

  @override
  State<ShodashaDonorApp> createState() => _ShodashaDonorAppState();
}

class _ShodashaDonorAppState extends State<ShodashaDonorApp> {
  late final ApiClient _api;
  late final AuthController _auth;
  late final BookingController _booking;
  late final AddressController _addresses;
  late final SelectedAddressStore _selectedStore;
  late final OrdersController _orders;
  late final ProfileController _profile;
  late final String _deviceId;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    _deviceId = await loadOrCreateDeviceId();
    _api = ApiClient(
      deviceId: _deviceId,
      accessTokenGetter: () => _auth.session?.accessToken,
      onUnauthorized: () => _auth.recoverSession(),
    );
    _auth = AuthController(
      api: ApiBackedAuthApi(_api),
      store: SecureSessionStore(),
      deviceId: _deviceId,
    );
    _booking = BookingController();
    _addresses = AddressController(api: _api);
    _selectedStore = SelectedAddressStore();
    unawaited(
      _selectedStore.load().then((_) {
        _addresses.bindSelection(_selectedStore);
      }),
    );
    _orders = OrdersController(repo: ApiBackedOrdersRepository(_api));
    _profile = ProfileController(api: _api);
    _auth.addListener(_onAuthBoundaryChanged);
    if (mounted) setState(() => _ready = true);
  }

  bool _wasAuthenticated = false;

  void _onAuthBoundaryChanged() {
    final authed = _auth.isAuthenticated;
    if (authed == _wasAuthenticated) return;
    _wasAuthenticated = authed;
    // Auth boundary: never let user B join a GET started by user A.
    _api.clearInflight();
    if (authed) return;
    _booking.resetUserScoped();
    _addresses.reset();
    _orders.reset();
    _profile.reset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    });
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
      navigatorKey: _navigatorKey,
      theme: buildShodashaTheme(),
      home: AuthGate(
        controller: _auth,
        home: DonorShell(
          api: _api,
          auth: _auth,
          booking: _booking,
          addresses: _addresses,
          orders: _orders,
          profile: _profile,
          razorpayKeyId: kRazorpayKeyId,
        ),
      ),
    );
  }
}
