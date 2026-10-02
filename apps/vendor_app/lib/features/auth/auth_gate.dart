// AuthGate: splash → restoreSession → vendor shell / login.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';
import 'otp_screen.dart';
import 'phone_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.home,
  });

  final AuthController controller;
  final Widget home;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    _restore();
  }

  Future<void> _restore() async {
    await widget.controller.restoreSession();
    if (mounted) setState(() => _restoring = false);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_drink, size: 64, color: ShodashaTheme.ink),
              SizedBox(height: 16),
              Text(
                'Shodasha Vendor',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }
    if (widget.controller.isAuthenticated) return widget.home;
    if (widget.controller.status == AuthStatus.codeSent ||
        widget.controller.status == AuthStatus.verifying) {
      return OtpScreen(controller: widget.controller);
    }
    return PhoneScreen(controller: widget.controller);
  }
}
