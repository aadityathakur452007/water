// F2 — OTP verify screen (FOtpField 6-digit + paste, adapted phone-not-email).
//
// ForUI pattern reused (see example_code/otp.ts): FOtpField single-purpose
// code input. ForUI is NOT in pubspec.yaml (F1 owns it), so the pattern is
// mirrored with Material: 6 auto-advancing boxes with full-code paste split.
//
// ui-checklist applied (Verifying Account): masked destination shown,
// incorrect/expired/max-attempts each get a specific message + next step
// (resend), 60s resend timer, success transitions out via [AuthGate].

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import 'auth_controller.dart';
import 'phone_screen.dart';

/// OTP verify. Pops itself (back to [AuthGate] → home) once authenticated.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.controller, this.onAuthenticated});

  final AuthController controller;
  final VoidCallback? onAuthenticated;

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
    if (widget.controller.isAuthenticated) {
      if (widget.onAuthenticated != null) {
        widget.onAuthenticated!();
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return;
    }
    // New backend error → error state + clear pin (retry, States.md).
    if (widget.controller.errorSeq != _seenErrorSeq) {
      _seenErrorSeq = widget.controller.errorSeq;
      _pin.setErrorState(true);
      _pin.clear();
      setState(() => _code = '');
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
    final errorColor = Theme.of(context).colorScheme.error;
    final digits = widget.controller.digits10;
    return Scaffold(
      backgroundColor: AuthTokens.bg,
      appBar: AppBar(
        backgroundColor: AuthTokens.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AuthTokens.text),
          tooltip: authStringsHi['editNumber'],
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final c = widget.controller;
              final verifying = c.status == AuthStatus.verifying;
              final canVerify =
                  _code.length == _length && !verifying && !c.mustResend;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    authStringsHi['otpTitle']!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AuthTokens.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${authStringsHi['otpSentTo']} ${digits.isNotEmpty ? maskPhone(digits) : ''}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AuthTokens.muted,
                    ),
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
                      borderRadius: BorderRadius.circular(AuthTokens.radius),
                      fillColor: AuthTokens.bg,
                      borderColor: AuthTokens.border,
                      focusedBorderColor: AuthTokens.blue,
                      errorBorderColor: Theme.of(context).colorScheme.error,
                    ),
                    onChanged: (v) {
                      widget.controller.clearError();
                      _pin.clearError();
                      setState(() => _code = v);
                    },
                    onCompleted: (_) => _submit(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${c.attempts}/${c.maxAttempts} • ${attemptsHi(c.attemptsLeft)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AuthTokens.muted,
                    ),
                  ),
                  if (c.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: errorColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              c.errorMessage!,
                              style: TextStyle(
                                color: errorColor,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (c.newDeviceAlert)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 16,
                            color: AuthTokens.blue,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              authStringsHi['newDevice']!,
                              style: const TextStyle(
                                color: AuthTokens.blue,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: AuthTokens.minTarget,
                    child: ElevatedButton(
                      onPressed: canVerify ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        // Locked spec: primary = black #111.
                        backgroundColor: AuthTokens.text,
                        foregroundColor: AuthTokens.bg,
                        disabledBackgroundColor: AuthTokens.text.withValues(
                          alpha: 0.3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AuthTokens.radius,
                          ),
                        ),
                      ),
                      child: verifying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AuthTokens.bg,
                              ),
                            )
                          : Text(authStringsHi['verify']!),
                    ),
                  ),
                  if (verifying)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        authStringsHi['verifying']!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AuthTokens.muted,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Center(
                    child: c.canResend
                        ? TextButton(
                            onPressed: verifying ? null : () => c.resend(),
                            style: TextButton.styleFrom(
                              foregroundColor: AuthTokens.blue,
                              minimumSize: const Size(
                                48,
                                AuthTokens.minTarget,
                              ),
                            ),
                            child: Text(authStringsHi['resend']!),
                          )
                        : Text(
                            resendInHi(c.resendInSeconds),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AuthTokens.muted,
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
