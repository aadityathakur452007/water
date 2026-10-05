// Vendor access-code screen: +91 number + admin-issued code → codeLogin.
// Demo sheet stays as the server-gated QA fallback. All CTAs ≥48dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart' show kSupportPhone;
import '../../core/theme.dart';
import 'auth_controller.dart';
import 'demo_sheet.dart';
import 'vendor_strings.dart';

class VendorCodeScreen extends StatefulWidget {
  const VendorCodeScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<VendorCodeScreen> createState() => _VendorCodeScreenState();
}

class _VendorCodeScreenState extends State<VendorCodeScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _phoneFocus = FocusNode();
  String? _phoneError;
  String? _codeError;
  bool _touchedPhone = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onAuth);
    _phoneFocus.addListener(_onPhoneFocus);
  }

  void _onAuth() {
    if (mounted) setState(() {});
  }

  void _onPhoneFocus() {
    if (!_phoneFocus.hasFocus && _touchedPhone) _validatePhone();
  }

  void _validatePhone() {
    setState(() {
      _phoneError = isValidIndianPhone(_phone.text)
          ? null
          : vendorStringsHi['phoneError'];
    });
  }

  void _validateCode() {
    setState(() {
      _codeError = isValidAccessCode(_code.text)
          ? null
          : vendorStringsHi['codeError'];
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onAuth);
    _phoneFocus.removeListener(_onPhoneFocus);
    _phone.dispose();
    _code.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final busy = c.status == AuthStatus.verifying;
    final valid =
        isValidIndianPhone(_phone.text) && isValidAccessCode(_code.text);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
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
              Text(
                vendorStringsHi['loginSubtitle']!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: ShodashaTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _phone,
                focusNode: _phoneFocus,
                keyboardType: TextInputType.phone,
                maxLength: 13,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                ],
                decoration: InputDecoration(
                  labelText: vendorStringsHi['phoneLabel'],
                  hintText: vendorStringsHi['phoneHint'],
                  prefixText: '+91 ',
                  errorText: _phoneError,
                  counterText: '',
                ),
                onChanged: (_) {
                  _touchedPhone = true;
                  widget.controller.clearError();
                  setState(() => _phoneError = null);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                keyboardType: TextInputType.visiblePassword,
                maxLength: 32,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: vendorStringsHi['codeLabel'],
                  hintText: vendorStringsHi['codeHint'],
                  errorText: _codeError,
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    tooltip: _obscure ? 'Code dikhayein' : 'Code chhupayein',
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onChanged: (_) {
                  widget.controller.clearError();
                  setState(() => _codeError = null);
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
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                onPressed: (!valid || busy)
                    ? null
                    : () {
                        _validatePhone();
                        _validateCode();
                        if (isValidIndianPhone(_phone.text) &&
                            isValidAccessCode(_code.text)) {
                          FocusScope.of(context).unfocus();
                          c.codeLogin(_phone.text, _code.text);
                        }
                      },
                child: Text(busy
                    ? vendorStringsHi['loggingIn']!
                    : vendorStringsHi['loginGo']!),
              ),
              const SizedBox(height: 12),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                onPressed: busy
                    ? null
                    : () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) =>
                              DemoSheet(controller: widget.controller),
                        ),
                child: Text(vendorStringsHi['demoLogin']!),
              ),
              const SizedBox(height: 8),
              Text(
                'Madad chahiye? $kSupportPhone',
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
