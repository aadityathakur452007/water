// Shodasha user app — F5 wiring: theme + API client + auth seams + 4-tab
// shell (Home/Orders/Support/Profile) + addresses/subscriptions routes.
//
// Guest-browse contract (user-flows flow 1): prices stay visible without
// login; OTP gates only booking commit + profile data (AuthGate routes the
// shell; ProfileScreen shows the login CTA when un-authed).

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/auth_impls.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'features/addresses/address_screen.dart';
import 'features/addresses/selected_address_store.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_gate.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Reads android/app/google-services.json; required before any FirebaseAuth
  // call (the login OTP flow). Failure here is fail-fast, never silent.
  await Firebase.initializeApp();
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

  @override
  void initState() {
    super.initState();
    _api = ApiClient(deviceId: 'pending-device');
    _auth = AuthController(
      api: ApiBackedAuthApi(_api),
      verifier: FirebasePhoneVerifier(),
      store: SecureSessionStore(),
      deviceId: 'pending-device',
    );
    _booking = BookingController(catalog: _HardcodedCatalog());
    _orders = OrdersController(repo: StubOrdersRepository());
    _addresses = AddressController(api: _api);
    _selectedStore = SelectedAddressStore();
    // Persistence behind the live selection: restore once, then the
    // controller writes through on every select (011_port).
    _selectedStore.load().then((_) {
      _addresses.bindSelection(_selectedStore);
    });
    _subs = SubscriptionController(api: _api);
    _profile = ProfileController(api: _api);
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

/// Offline fallback rates (contract §4.2 catalog values).
class _HardcodedCatalog implements CatalogApi {
  @override
  Future<CatalogRates> fetchRates() async => const CatalogRates();
}
