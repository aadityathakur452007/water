// S2 — Auth gate: cold-start restore splash → authenticated home / register.
//
// Guest-browse law (user-flows flow 1): prices are NEVER walled behind
// login. A valid session routes straight to [home]; without one the gate
// shows the register screen and its guest action drops into [home] as a
// guest. Register is enforced only at booking commit OR profile, via
// [openRegister] (returns true when the user ends up authenticated).
//
// States.md covered: splash (page loading / in-flight restore),
// authenticated, guest user, session expired → register (redirecting),
// logged out, in-flight action.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';
import 'name_number_screen.dart';

/// Splash → home/register router. Restores the session on first mount.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.controller, required this.home});

  final AuthController controller;
  final Widget home;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _ready = false;
  bool _guest = false;
  bool _restoreFailed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onAuthChanged);
    _boot();
  }

  Future<void> _boot() async {
    var restored = false;
    try {
      restored = await widget.controller.restoreSession();
    } catch (_) {
      // restoreSession owns its timeout/error path; this is belt-and-braces
      // so no unexpected throw can leave the splash mounted.
    }
    if (!mounted) return;
    setState(() {
      _restoreFailed = !restored;
      _ready = true;
    });
  }

  void _onAuthChanged() {
    // Logout / expired wipe always returns to register — never strand guest
    // UI on a dead session (legacy gate behavior).
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
        if (!_ready) return const _AuthSplash();
        if (widget.controller.isAuthenticated || _guest) return widget.home;
        return NameNumberScreen(
          controller: widget.controller,
          notice: _restoreFailed
              ? 'Couldn’t restore your session. Sign in again.'
              : null,
          onGuestBrowse: () => setState(() => _guest = true),
        );
      },
    );
  }
}

/// Pushes the register screen and reports whether the user is authenticated
/// afterwards. Used by future booking/profile gates; guest browsing still
/// exits normally with false (no dead end).
Future<bool> openRegister(
  BuildContext context,
  AuthController controller,
) async {
  if (controller.isAuthenticated) return true;
  await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (routeContext) => NameNumberScreen(
        controller: controller,
        onGuestBrowse: () => Navigator.of(routeContext).pop(false),
        onRegistered: () => Navigator.of(routeContext).pop(true),
      ),
    ),
  );
  return controller.isAuthenticated;
}

/// Branded cold-start splash while secure-storage restore is in flight.
class _AuthSplash extends StatelessWidget {
  const _AuthSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/logo.png',
                width: 72,
                height: 72,
                cacheWidth: 144,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.water_drop,
                  size: 56,
                  color: ShodashaTheme.teal,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Shodasha',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: ShodashaTheme.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'RO+UV • Lab-tested water',
                style: TextStyle(fontSize: 13, color: ShodashaTheme.muted),
              ),
              const SizedBox(height: 16),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ShodashaTheme.teal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
