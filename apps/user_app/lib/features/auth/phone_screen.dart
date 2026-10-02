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
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';
import 'demo_sheet.dart';
import 'otp_screen.dart';

/// F2 auth tokens — aliases of [ShodashaTheme] (Wave 1 honesty: the
/// feature-local blues #0369A1 drifted from the locked #0284C7; a single
/// source keeps them from drifting again).
class AuthTokens {
  static const Color bg = ShodashaTheme.bg;
  static const Color text = ShodashaTheme.ink;
  static const Color muted = ShodashaTheme.muted;
  static const Color blue = ShodashaTheme.blue;
  static const Color border = ShodashaTheme.border;
  static const double radius = ShodashaTheme.radius;
  static const double minTarget = ShodashaTheme.minTarget;
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

  /// Staggered hero entrance (fade + gentle rise/fall, ≤300ms, easeOut —
  /// the welcome-rhythm recipe). Static render on reduced motion. Inputs
  /// stay un-animated (keyboard-jank guard).
  Widget _rise(Widget child, {double begin = 0, int delayMs = 0}) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return child
        .animate(delay: Duration(milliseconds: delayMs))
        .fade(duration: 250.ms)
        .slideY(
          begin: begin,
          end: 0,
          duration: 300.ms,
          curve: Curves.easeOut,
        );
  }

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
              // Generous top space per the hero rhythm (mark → headline →
              // sub → CTA cascade below).
              const SizedBox(height: 48),
              // Designed hero: brand card + factual trust chips (UPI+COD and
              // WhatsApp help are real product facts — no invented claims).
              _rise(
                Card(
                  shape: ShodashaTheme.shape,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/logo.png',
                          width: 56,
                          height: 56,
                          cacheWidth: 112,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.water_drop,
                            size: 44,
                            color: AuthTokens.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Shodasha',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AuthTokens.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                authStringsHi['trustLine']!,
                                style: const TextStyle(
                                    fontSize: 13, color: AuthTokens.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                begin: -0.2,
              ),
              const SizedBox(height: 12),
              _rise(
                const Row(
                  children: [
                    Chip(
                      avatar: Icon(Icons.payments_outlined, size: 16),
                      label: Text('UPI + COD'),
                    ),
                    SizedBox(width: 8),
                    Chip(
                      avatar: Icon(Icons.support_agent_outlined, size: 16),
                      label: Text('WhatsApp help'),
                    ),
                  ],
                ),
                begin: -0.1,
                delayMs: 60,
              ),
              const SizedBox(height: 24),
              const Text(
                'Step 1 / 2 — Mobile number',
                style: TextStyle(fontSize: 12, color: AuthTokens.muted),
              ),
              const SizedBox(height: 6),
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
                  labelText: 'Mobile number',
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
                      _rise(
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
                        begin: 0.2,
                        delayMs: 120,
                      ),
                      if (sending)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(),
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
                child: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => UserDemoSheet(
                      controller: widget.controller,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AuthTokens.blue,
                    minimumSize: const Size(48, AuthTokens.minTarget),
                  ),
                  child: Text(authStringsHi['demoLogin']!),
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
