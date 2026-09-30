// F2 — Auth gate: splash → home / login router by session validity.
//
// Guest-browse rule (user-flows flow 1): prices are NEVER walled behind login.
// The gate routes a valid session straight to [home]; without a session it
// shows login, and login's guest action drops into [home] as a guest. OTP is
// therefore enforced only at booking commit OR profile (F3 wires those gates
// against AuthController.isAuthenticated).
//
// States.md covered: splash (page loading), authenticated, guest user,
// session expired → login (redirecting), logged out.

import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'phone_screen.dart';

/// Splash → home/login router.
///
/// [home] is F3's catalog home (public, guest-browsable). [loginBuilder]
/// defaults to [PhoneScreen] with guest-browse wired back into the gate.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.home,
    this.loginBuilder,
  });

  final AuthController controller;
  final Widget home;
  final Widget Function(
    BuildContext context,
    AuthController controller,
    VoidCallback onGuestBrowse,
  )? loginBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _ready = false;
  bool _guest = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onAuthChanged);
    _boot();
  }

  Future<void> _boot() async {
    await widget.controller.restoreSession();
    if (mounted) setState(() => _ready = true);
  }

  void _onAuthChanged() {
    // Logout (or expired wipe) always returns to login — never strand guest UI.
    if (widget.controller.status == AuthStatus.idle && _guest) {
      setState(() => _guest = false);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (!_ready) return const SplashScreen();
        if (widget.controller.isAuthenticated || _guest) return widget.home;
        final custom = widget.loginBuilder;
        if (custom != null) {
          return custom(
            context,
            widget.controller,
            () => setState(() => _guest = true),
          );
        }
        return PhoneScreen(
          controller: widget.controller,
          onGuestBrowse: () => setState(() => _guest = true),
        );
      },
    );
  }
}

/// Cold-start splash (white, brand + loader — Mode-1, no decoration).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AuthTokens.bg,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Shodasha',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AuthTokens.text,
                ),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AuthTokens.blue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
