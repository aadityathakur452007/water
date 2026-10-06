// User demo sheet: seeded customer phone + code, no OTP round-trip.
// Server gates the door (config flag + demo_codes row); closed in prod the
// confirm just surfaces the error. QA-only convenience, no secrets.

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

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final busy = _busy || c.status == AuthStatus.verifying;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              authStringsHi['demoTitle']!,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              authStringsHi['demoHint']!,
              style: const TextStyle(color: ShodashaTheme.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      _phone.text = '+919000000001';
                      _code.text = '111111';
                    }),
              child: Text(authStringsHi['demoCustomer']!),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              // WHY: 16px stops iOS auto-zoom (mobile-native A4).
              style: const TextStyle(fontSize: 16),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              ],
              decoration: InputDecoration(
                labelText: authStringsHi['phoneLabel'],
              ),
            ),
            TextField(
              controller: _code,
              // WHY: 16px stops iOS auto-zoom (mobile-native A4).
              style: const TextStyle(fontSize: 16),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Demo code'),
            ),
            if (c.errorMessage != null) ...[
              const SizedBox(height: 8),
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
                      c.errorMessage!,
                      style: const TextStyle(color: ShodashaTheme.danger),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final ok = await c.demoLogin(_phone.text, _code.text);
                      if (context.mounted && ok) {
                        Navigator.of(context).pop();
                      } else if (context.mounted) {
                        setState(() => _busy = false);
                      }
                    },
              child: Text(_busy ? 'Login ho raha…' : authStringsHi['demoGo']!),
            ),
          ],
        ),
      ),
    );
  }
}
