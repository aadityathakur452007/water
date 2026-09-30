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
  late final List<TextEditingController> _boxes;
  late final List<FocusNode> _nodes;
  int _seenErrorSeq = 0;

  @override
  void initState() {
    super.initState();
    _boxes = List.generate(_length, (_) => TextEditingController());
    _nodes = List.generate(_length, (_) => FocusNode());
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
    // New backend error → clear boxes, restart at box 0 (retry, States.md).
    if (widget.controller.errorSeq != _seenErrorSeq) {
      _seenErrorSeq = widget.controller.errorSeq;
      for (final box in _boxes) {
        box.clear();
      }
      _nodes.first.requestFocus();
      setState(() {});
    }
  }

  /// Pasted full code (or typed char) lands in box [index] — split across rest.
  void _onBoxChanged(int index, String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      for (var i = 0; i < _length; i++) {
        _boxes[i].text = i - index < digits.length && i >= index
            ? digits[i - index]
            : (i < index ? _boxes[i].text : '');
      }
      _nodes.last.requestFocus();
    } else {
      _boxes[index].text = digits; // single char or cleared
      if (digits.isNotEmpty && index < _length - 1) {
        _nodes[index + 1].requestFocus();
      } else if (digits.isEmpty && index > 0) {
        _nodes[index - 1].requestFocus();
      }
    }
    widget.controller.clearError();
    setState(() {});
  }

  String get _code => _boxes.map((b) => b.text).join();

  Future<void> _submit() async {
    if (_code.length != _length) return;
    FocusScope.of(context).unfocus();
    await widget.controller.confirm(_code);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onAuthChanged);
    for (final box in _boxes) {
      box.dispose();
    }
    for (final node in _nodes) {
      node.dispose();
    }
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
                  Row(
                    children: [
                      for (var i = 0; i < _length; i++) ...[
                        Expanded(
                          child: SizedBox(
                            height: 56, // ≥48dp target (mobile-native)
                            child: TextField(
                              controller: _boxes[i],
                              focusNode: _nodes[i],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                color: AuthTokens.text,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(_length),
                              ],
                              decoration: InputDecoration(
                                counterText: '',
                                contentPadding: EdgeInsets.zero,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AuthTokens.radius,
                                  ),
                                  borderSide: const BorderSide(
                                    color: AuthTokens.border,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AuthTokens.radius,
                                  ),
                                  borderSide: const BorderSide(
                                    color: AuthTokens.blue,
                                  ),
                                ),
                              ),
                              onChanged: (v) => _onBoxChanged(i, v),
                            ),
                          ),
                        ),
                        if (i < _length - 1) const SizedBox(width: 8),
                      ],
                    ],
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
