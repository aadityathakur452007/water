// Donor auth gate: cold-start restore splash → donor login / customer shell.
//
// This clone intentionally has no guest-browse door: the donor customer app
// is login-first. Session restore still gets the 032 timeout so a hung
// keychain can never strand the splash.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.controller, required this.home});

  final AuthController controller;
  final Widget home;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _ready = false;
  bool _restoreFailed = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    var restored = false;
    try {
      restored = await widget.controller.restoreSession();
    } catch (_) {
      // restoreSession owns its timeout/error path; belt and braces so no
      // unexpected throw can leave the splash mounted.
    }
    if (!mounted) return;
    setState(() {
      _restoreFailed = !restored;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (!_ready) return const _AuthSplash();
        if (widget.controller.isAuthenticated) return widget.home;
        return DonorLoginScreen(
          controller: widget.controller,
          notice: _restoreFailed
              ? "Couldn't restore your session. Sign in again."
              : null,
        );
      },
    );
  }
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
                'RO+UV · Lab-tested water',
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
