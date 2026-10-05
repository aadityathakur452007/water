// F2 (028) — Name+number entry screen: naam + mobile → registerNameNumber.
//
// No OTP, no SMS round-trip. Guest browse keeps prices visible WITHOUT
// login (user-flows flow 1); demo sheet stays as the server-gated QA
// fallback. All CTAs ≥48dp. Inputs stay un-animated (keyboard-jank guard).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/api_client.dart' show kSupportPhone;
import '../../core/theme.dart';
import 'auth_controller.dart';
import 'demo_sheet.dart';

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

/// Name+number entry. [onGuestBrowse] keeps prices visible WITHOUT login
/// (user-flows flow 1).
class NameNumberScreen extends StatefulWidget {
  const NameNumberScreen({
    super.key,
    required this.controller,
    this.onGuestBrowse,
  });

  final AuthController controller;
  final VoidCallback? onGuestBrowse;

  @override
  State<NameNumberScreen> createState() => _NameNumberScreenState();
}

class _NameNumberScreenState extends State<NameNumberScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  bool _touched = false; // errors show only after submit or focus-loss

  @override
  void initState() {
    super.initState();
    _name.addListener(_onChanged);
    _phone.addListener(_onChanged);
    _phoneFocus.addListener(_onFocusChanged);
  }

  void _onChanged() {
    widget.controller.clearError();
    setState(() {}); // recompute button state silently — no error while typing
  }

  void _onFocusChanged() {
    if (!_phoneFocus.hasFocus && _phone.text.isNotEmpty && !_touched) {
      setState(() => _touched = true); // ui-checklist: signal after loss of focus
    } else if (_phoneFocus.hasFocus && _touched) {
      setState(() => _touched = false); // default state returns on re-attempt
    }
  }

  bool get _validName => isValidUserName(_name.text);
  bool get _validPhone => isValidIndianPhone(_phone.text);
  bool get _valid => _validName && _validPhone;

  String? get _nameError =>
      (_touched && !_validName) ? authStringsHi['nameError'] : null;
  String? get _phoneError =>
      (_touched && !_validPhone) ? authStringsHi['phoneError'] : null;

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
    await widget.controller.registerNameNumber(_name.text, _phone.text);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
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
                'Naam + Mobile number',
                style: TextStyle(fontSize: 12, color: AuthTokens.muted),
              ),
              const SizedBox(height: 6),
              Text(
                authStringsHi['registerTitle']!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AuthTokens.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                authStringsHi['registerSubtitle']!,
                style: const TextStyle(fontSize: 14, color: AuthTokens.muted),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                focusNode: _nameFocus,
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
                maxLength: 100,
                // WHY: 16px stops iOS auto-zoom (mobile-native §4); harmless on Android.
                style: const TextStyle(fontSize: 16, color: AuthTokens.text),
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: authStringsHi['nameLabel'],
                  hintText: authStringsHi['nameHint'],
                  counterText: '',
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
                  errorText: _nameError,
                  errorStyle: TextStyle(color: errorColor, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                focusNode: _phoneFocus,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 16, color: AuthTokens.text),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: authStringsHi['phoneLabel'],
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
                  errorText: _phoneError,
                  errorStyle: TextStyle(color: errorColor, fontSize: 13),
                ),
              ),
              const SizedBox(height: 24),
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final registering =
                      widget.controller.status == AuthStatus.verifying;
                  final apiError = widget.controller.errorMessage;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _rise(
                        SizedBox(
                          height: AuthTokens.minTarget,
                          child: ElevatedButton(
                            // WHY: disabled until valid (no dead taps, no spam register).
                            onPressed:
                                (!_valid || registering) ? null : _submit,
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
                            child: registering
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AuthTokens.bg,
                                    ),
                                  )
                                : Text(authStringsHi['registerGo']!),
                          ),
                        ),
                        begin: 0.2,
                        delayMs: 120,
                      ),
                      if (registering)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(),
                        ),
                      if (registering)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            authStringsHi['registering']!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AuthTokens.muted,
                            ),
                          ),
                        ),
                      if (apiError != null)
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
                      if (widget.controller.newDeviceAlert)
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
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Madad chahiye? $kSupportPhone',
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
