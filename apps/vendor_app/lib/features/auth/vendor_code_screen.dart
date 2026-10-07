// Vendor access-code screen: +91 number + admin-issued code → codeLogin.
// Demo sheet stays as the server-gated QA fallback. All CTAs ≥48dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

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
                maxLength: 10,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(
                  labelText: vendorStringsHi['phoneLabel'],
                  hintText: '10-digit number',
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
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ShodashaTheme.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ShodashaTheme.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.error_outline,
                              size: 16, color: ShodashaTheme.danger),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              c.errorMessage!,
                              style: const TextStyle(
                                color: ShodashaTheme.danger,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () {
                          launchUrlString(
                            'https://wa.me/917828442476?text=Namaste%20Admin%2C%20mujhe%20login%20me%20problem%20aa%20rahi%20hai',
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        child: const Row(
                          children: [
                            Icon(Icons.chat, size: 14, color: ShodashaTheme.ink),
                            SizedBox(width: 4),
                            Text(
                              'Admin WhatsApp: 7828442476 par sampark karein',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Admin WhatsApp Support: 7828442476'),
                onPressed: () {
                  launchUrlString(
                    'https://wa.me/917828442476?text=Namaste%20Admin%2C%20mujhe%20Vendor%20app%20me%20madad%20chahiye',
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              const SizedBox(height: 8),
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
            ],
          ),
        ),
      ),
    );
  }
}
