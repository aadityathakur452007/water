// Vendor phone screen: +91 field, focus-loss errors, disabled-until-valid.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';
import 'vendor_strings.dart';

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onAuth);
    _focus.addListener(_onFocus);
  }

  void _onAuth() {
    if (mounted) setState(() {});
  }

  void _onFocus() {
    if (!_focus.hasFocus && _touched) _validate();
  }

  void _validate() {
    final ok = isValidIndianPhone(_ctrl.text);
    setState(() {
      _error = ok ? null : vendorStringsHi['phoneError'];
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onAuth);
    _focus.removeListener(_onFocus);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final sending = c.status == AuthStatus.sending;
    final valid = isValidIndianPhone(_ctrl.text);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              const Icon(Icons.local_drink, size: 64, color: ShodashaTheme.ink),
              const SizedBox(height: 16),
              Text(
                vendorStringsHi['appName']!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                vendorStringsHi['loginTitle']!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: ShodashaTheme.muted),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _ctrl,
                focusNode: _focus,
                keyboardType: TextInputType.phone,
                maxLength: 13,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                ],
                decoration: InputDecoration(
                  labelText: vendorStringsHi['phoneLabel'],
                  hintText: vendorStringsHi['phoneHint'],
                  prefixText: '+91 ',
                  errorText: _error,
                  counterText: '',
                ),
                onChanged: (_) {
                  _touched = true;
                  widget.controller.clearError();
                  setState(() {
                    _error = null;
                  });
                },
              ),
              if (c.errorMessage != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: ShodashaTheme.danger),
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
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: (!valid || sending)
                    ? null
                    : () {
                        _validate();
                        if (isValidIndianPhone(_ctrl.text)) {
                          c.sendOtp(_ctrl.text);
                        }
                      },
                child: Text(sending
                    ? vendorStringsHi['sending']!
                    : vendorStringsHi['sendOtp']!),
              ),
              const SizedBox(height: 12),
              Text(
                vendorStringsHi['loginSubtitle']!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: ShodashaTheme.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
