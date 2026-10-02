// Vendor demo sheet: seeded vendor phone + code, no OTP round-trip.
// Server gates the door (config flag + demo_codes row); closed in prod the
// confirm just surfaces the Hindi error. QA-only convenience, no secrets.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';
import 'vendor_strings.dart';

class DemoSheet extends StatefulWidget {
  const DemoSheet({super.key, required this.controller});

  final AuthController controller;

  @override
  State<DemoSheet> createState() => _DemoSheetState();
}

class _DemoSheetState extends State<DemoSheet> {
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
            Text(vendorStringsHi['demoTitle']!,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            Text(vendorStringsHi['demoHint']!,
                style: const TextStyle(color: ShodashaTheme.muted)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                        _phone.text = '+919000000002';
                        _code.text = '222222';
                      }),
              child: Text(vendorStringsHi['demoVendor']!),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))
              ],
              decoration: InputDecoration(
                  labelText: vendorStringsHi['phoneLabel']),
            ),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Demo code'),
            ),
            if (c.errorMessage != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: ShodashaTheme.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(c.errorMessage!,
                        style: const TextStyle(
                            color: ShodashaTheme.danger)),
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
              child: Text(
                  _busy ? 'Login ho raha…' : vendorStringsHi['demoGo']!),
            ),
          ],
        ),
      ),
    );
  }
}
