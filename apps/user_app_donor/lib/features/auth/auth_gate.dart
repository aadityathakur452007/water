// Donor auth gate: cold-start restore splash → donor login / customer shell.
//
// Login-first. Session restore keeps the 032 5s timeout so a hung keychain can
// never strand the splash. 034 adds the one-shot session-expiry notice: a
// forced 401/403 wipe explains why the user is back at login; manual logout
// never gets that copy.

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
  String? _gateNotice;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onAuthChanged);
    _boot();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onAuthChanged);
    super.dispose();
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
    final expiryNotice = widget.controller.sessionNotice;
    setState(() {
      _restoreFailed = !restored;
      _gateNotice =
          expiryNotice ??
          (!restored ? "Couldn't restore your session. Sign in again." : null);
      _ready = true;
    });
    if (expiryNotice != null) _consumeExpiryNotice();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (widget.controller.isAuthenticated) {
      if (_gateNotice != null) setState(() => _gateNotice = null);
      return;
    }
    final expiryNotice = widget.controller.sessionNotice;
    if (expiryNotice == null) return;
    setState(() => _gateNotice = expiryNotice);
    _consumeExpiryNotice();
  }

  /// Clear the controller's one-shot flag after the frame that displays it.
  void _consumeExpiryNotice() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.clearSessionNotice();
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
          notice:
              _gateNotice ??
              (_restoreFailed
                  ? "Couldn't restore your session. Sign in again."
                  : null),
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
