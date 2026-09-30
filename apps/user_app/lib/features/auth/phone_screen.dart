// F2 — Phone entry screen (ForUI phone field, adapted phone-not-email).
//
// ForUI pattern reused (see example_code/login.ts): labelled field + hint,
// inline validator, primary button gated on form validity. ForUI is NOT in
// pubspec.yaml (F1 owns it), so the pattern is mirrored with Material — same
// structure, same tokens, zero new deps.
//
// ui-checklist applied: Login Page (logo/title/phone-id; no password or
// third-party in v1 — phone OTP only per contract §4.1) + Input Field
// (label/placeholder/numeric/hint) + Showing Input Error (validate on
// focus-loss, never while typing; error icon + text; default state returns
// on re-attempt).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_controller.dart';
import 'otp_screen.dart';

/// F2 auth tokens — single source for the auth feature (Mode-1 restraint:
/// one accent, hairline borders, no gradients/shadows/emoji).
class AuthTokens {
  static const Color bg = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF111111);
  static const Color muted = Color(0xFF595959);
  static const Color blue = Color(0xFF0369A1);
  static const Color border = Color(0xFFE5E5E5);
  static const double radius = 8;
  static const double minTarget = 48;
}

/// Phone entry. [onGuestBrowse] keeps prices visible WITHOUT login
/// (user-flows flow 1); [onCodeSent] overrides the default push of [OtpScreen].
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({
    super.key,
    required this.controller,
    this.onGuestBrowse,
    this.onCodeSent,
  });

  final AuthController controller;
  final VoidCallback? onGuestBrowse;
  final VoidCallback? onCodeSent;

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  bool _touched = false; // error shows only after focus-loss or submit

  @override
  void initState() {
    super.initState();
    _field.addListener(_onChanged);
    _focus.addListener(_onFocusChanged);
  }

  void _onChanged() {
    widget.controller.clearError();
    setState(() {}); // recompute button state silently — no error while typing
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus && _field.text.isNotEmpty && !_touched) {
      setState(() => _touched = true); // ui-checklist: signal after loss of focus
    } else if (_focus.hasFocus && _touched) {
      setState(() => _touched = false); // default state returns on re-attempt
    }
  }

  bool get _valid => isValidIndianPhone(_field.text);
  String? get _error =>
      (_touched && !_valid) ? authStringsHi['phoneError'] : null;

  Future<void> _submit() async {
    setState(() => _touched = true);
    if (!_valid) return;
    FocusScope.of(context).unfocus();
    await widget.controller.sendOtp(_field.text);
    if (!mounted) return;
    if (widget.controller.status == AuthStatus.codeSent) {
      if (widget.onCodeSent != null) {
        widget.onCodeSent!();
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OtpScreen(controller: widget.controller),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Scaffold(
      backgroundColor: AuthTokens.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Text(
                'Shodasha',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AuthTokens.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                authStringsHi['trustLine']!,
                style: const TextStyle(fontSize: 13, color: AuthTokens.muted),
              ),
              const SizedBox(height: 32),
              Text(
                authStringsHi['loginTitle']!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AuthTokens.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                authStringsHi['loginSubtitle']!,
                style: const TextStyle(fontSize: 14, color: AuthTokens.muted),
              ),
              const SizedBox(height: 24),
              const Text(
                'Mobile number',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AuthTokens.text,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _field,
                focusNode: _focus,
                keyboardType: TextInputType.phone,
                // WHY: 16px stops iOS auto-zoom (mobile-native §4); harmless on Android.
                style: const TextStyle(fontSize: 16, color: AuthTokens.text),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: authStringsHi['phoneHint'],
                  helperText: authStringsHi['phoneHelper'],
                  helperStyle: const TextStyle(color: AuthTokens.muted),
                  prefixText: '+91 ',
                  prefixStyle: const TextStyle(
                    fontSize: 16,
                    color: AuthTokens.text,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AuthTokens.radius),
                    borderSide: const BorderSide(color: AuthTokens.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AuthTokens.radius),
                    borderSide: const BorderSide(color: AuthTokens.blue),
                  ),
                  errorText: _error,
                  errorStyle: TextStyle(color: errorColor, fontSize: 13),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  // WHY: icon + text, never color alone (ui-checklist + a11y).
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 16, color: errorColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: errorColor, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final sending =
                      widget.controller.status == AuthStatus.sending;
                  final apiError = widget.controller.errorMessage;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: AuthTokens.minTarget,
                        child: ElevatedButton(
                          // WHY: disabled until valid (no dead taps, no spam OTP).
                          onPressed: (!_valid || sending) ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            // Locked spec: primary = black #111 (blue is for
                            // links/active/water cues only).
                            backgroundColor: AuthTokens.text,
                            foregroundColor: AuthTokens.bg,
                            disabledBackgroundColor: AuthTokens.text
                                .withValues(alpha: 0.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AuthTokens.radius,
                              ),
                            ),
                          ),
                          child: sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AuthTokens.bg,
                                  ),
                                )
                              : Text(authStringsHi['sendOtp']!),
                        ),
                      ),
                      if (sending)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            authStringsHi['sending']!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AuthTokens.muted,
                            ),
                          ),
                        ),
                      if (apiError != null && _touched)
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
                                  apiError,
                                  style: TextStyle(
                                    color: errorColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              if (widget.onGuestBrowse != null)
                Center(
                  child: TextButton(
                    onPressed: widget.onGuestBrowse,
                    style: TextButton.styleFrom(
                      foregroundColor: AuthTokens.blue,
                      minimumSize: const Size(48, AuthTokens.minTarget),
                    ),
                    child: Text(authStringsHi['guestBrowse']!),
                  ),
                ),
              Center(
                child: Text(
                  authStringsHi['guestNote']!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AuthTokens.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
