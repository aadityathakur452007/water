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
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_sheet.dart';
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
    return AppSheet(
      title: 'Demo login',
      onClose: _busy ? null : () => Navigator.of(context).pop(),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(label: 'Login with demo', busy: _busy, onPressed: _login),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'If the demo door is closed, sign in with your mobile number and '
            'password. Demo codes are checked only by the server.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: ShodashaTheme.muted,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Seeded QA account. The server decides whether the demo door '
            'is open.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: ShodashaTheme.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _phone.text = '+919000000001';
                    _code.text = '111111';
                  }),
            icon: const Icon(Icons.auto_fix_high_outlined, size: 20),
            label: const Text('Fill demo customer'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, ShodashaTheme.minTarget),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _phone,
            enabled: !_busy,
            // 16px stops mobile browser auto-zoom.
            style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            ],
            decoration: const InputDecoration(labelText: 'Mobile number'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _code,
            enabled: !_busy,
            style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Demo code'),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 18,
                  color: ShodashaTheme.danger,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: ShodashaTheme.danger,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
