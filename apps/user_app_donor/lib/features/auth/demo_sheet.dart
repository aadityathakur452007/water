// S2 — Demo login sheet (legacy demo_sheet port, donor-styled).
//
// QA convenience only: the seeded phone + code are prefilled, but the
// SERVER owns the door (config flag + demo_codes row). A closed door
// surfaces the server error verbatim — never a local/fake success. The
// customer-app role gate lives in AuthController.demoLogin (non-user roles
// are wiped).
//
// States.md covered: form filled/submitting/failed, action retry available,
// auth guest, honest error; loading disables the confirm.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';

class UserDemoSheet extends StatefulWidget {
  const UserDemoSheet({super.key, required this.controller});

  final AuthController controller;

  @override
  State<UserDemoSheet> createState() => _UserDemoSheetState();
}

class _UserDemoSheetState extends State<UserDemoSheet> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _busy = true);
    final ok = await widget.controller.demoLogin(_phone.text, _code.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _busy = false); // error row renders from controller
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.controller.errorMessage;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ShodashaTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Demo login',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                color: ShodashaTheme.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Seeded QA account. The server decides whether the demo door '
              'is open.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: ShodashaTheme.muted,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _phone.text = '+919000000001';
                      _code.text = '111111';
                    }),
              child: const Text('Fill demo customer'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              // WHY: 16px stops iOS auto-zoom (mobile-native §4).
              style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              ],
              decoration: const InputDecoration(labelText: 'Mobile number'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Demo code'),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: ShodashaTheme.danger,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(
                        color: ShodashaTheme.danger,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _busy ? null : _login,
                style: ElevatedButton.styleFrom(
                  // Auth action, not money → ink (green stays money-only).
                  backgroundColor: ShodashaTheme.ink,
                  foregroundColor: ShodashaTheme.bg,
                  disabledBackgroundColor: ShodashaTheme.ink.withValues(
                    alpha: 0.3,
                  ),
                  disabledForegroundColor: ShodashaTheme.surface,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: ShodashaTheme.surface,
                        ),
                      )
                    : const Text('Login with demo'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'If the demo door is closed, sign in above with your mobile '
              'number and password. Demo codes are checked only by the server.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: ShodashaTheme.muted),
            ),
          ],
        ),
      ),
    );
  }
}
