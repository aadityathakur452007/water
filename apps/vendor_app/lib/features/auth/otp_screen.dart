// Vendor OTP screen: MaterialPinField 6-digit (pin_code_fields 9.4.0),
// masked number, 60s resend, 5-attempt force-resend, expired path.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';
import 'vendor_strings.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const int _length = 6;
  late final PinInputController _pin;
  int _seenErrorSeq = 0;
  String _code = '';

  @override
  void initState() {
    super.initState();
    _pin = PinInputController();
    _seenErrorSeq = widget.controller.errorSeq;
    widget.controller.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (widget.controller.errorSeq != _seenErrorSeq) {
      _seenErrorSeq = widget.controller.errorSeq;
      _pin.setErrorState(true);
      _pin.clear();
      setState(() => _code = '');
    } else {
      setState(() {});
    }
  }

  Future<void> _submit() async {
    if (_code.length != _length) return;
    FocusScope.of(context).unfocus();
    await widget.controller.confirm(_code);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onAuthChanged);
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final verifying = c.status == AuthStatus.verifying;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: vendorStringsHi['editNumber'],
          onPressed: () => c.logout(),
        ),
        title: Text(vendorStringsHi['editNumber']!),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                vendorStringsHi['otpTitle']!,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${vendorStringsHi['otpSentTo']} ${maskPhone(c.digits10)}',
                style: const TextStyle(color: ShodashaTheme.muted),
              ),
              const SizedBox(height: 24),
              MaterialPinField(
                length: _length,
                pinController: _pin,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                enableAutofill: true,
                enablePaste: true,
                theme: MaterialPinTheme(
                  shape: MaterialPinShape.outlined,
                  cellSize: const Size(48, 56),
                  spacing: 8,
                  borderRadius:
                      BorderRadius.circular(ShodashaTheme.radius),
                  fillColor: ShodashaTheme.bg,
                  borderColor: ShodashaTheme.border,
                  focusedBorderColor: ShodashaTheme.blue,
                  errorBorderColor: ShodashaTheme.danger,
                ),
                onChanged: (v) {
                  c.clearError();
                  _pin.clearError();
                  setState(() => _code = v);
                },
                onCompleted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              Text(
                attemptsHi(c.attemptsLeft),
                style: const TextStyle(color: ShodashaTheme.muted),
              ),
              if (c.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 16, color: ShodashaTheme.danger),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          c.errorMessage!,
                          style: const TextStyle(
                              color: ShodashaTheme.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: (_code.length != _length || verifying)
                    ? null
                    : _submit,
                child: Text(verifying
                    ? vendorStringsHi['verifying']!
                    : vendorStringsHi['verify']!),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed:
                    c.canResend && !verifying ? () => c.resend() : null,
                child: Text(c.canResend
                    ? vendorStringsHi['resend']!
                    : resendInHi(c.resendInSeconds)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
