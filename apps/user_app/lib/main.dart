// Shodasha user app (032-user-app-replacement) — S1 composition root:
// device id + ApiClient + AuthController + 5-tab shell skeleton.
//
// Guest-browse contract (user-flows flow 1): prices stay visible without
// login; register gates only booking commit + profile data. The full
// AuthGate + register screen land in S2 (auth/onboarding); this build
// boots straight into the shell.

import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/auth_impls.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/shell/user_shell.dart';

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

/// Composition root: one ApiClient + AuthController shared by the shell
/// and pushed routes (feature controllers attach in their slices).
class ShodashaApp extends StatefulWidget {
  const ShodashaApp({super.key});

  @override
  State<ShodashaApp> createState() => _ShodashaAppState();
}

class _ShodashaAppState extends State<ShodashaApp> {
  late final ApiClient _api;
  late final AuthController _auth;
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
  /// server). Session restore is best-effort — failure = guest.
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
    await _auth.restoreSession();
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
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
      home: const UserShell(),
    );
  }
}
