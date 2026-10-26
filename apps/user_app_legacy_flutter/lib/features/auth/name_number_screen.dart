// F2 — Name+email+number entry screen: naam + email + mobile → registerNameNumber.
//
// No OTP, no SMS round-trip. Guest browse keeps prices visible WITHOUT
// login (user-flows flow 1); demo sheet stays as the server-gated QA
// fallback. All CTAs ≥48dp. Inputs stay un-animated (keyboard-jank guard).
//
// 031: donor login_screen skeleton transplanted (welcome band with brand
// mark + centered title, label-above fields, teal 2px focus ring, 52dp flat
// ink CTA) — locked palette v2 tokens only, zero string/logic changes
// (behavior tests assert exact copy).

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
  // 031: teal rides structure/brand (law) — welcome band mark, focus rings.
  static const Color teal = ShodashaTheme.teal;
  static const Color tealTint = ShodashaTheme.tealTint;
  static const Color surface = ShodashaTheme.surface;
  static const double radius = ShodashaTheme.radius;
  static const double minTarget = ShodashaTheme.minTarget;
}

/// Donor field-label grammar: small bold label sittings above the field,
/// hint stays in-field. Same string data as before (freeze-safe).
const TextStyle _fieldLabel = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w800,
  color: AuthTokens.text,
);

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
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  bool _touched = false; // errors show only after submit or focus-loss

  @override
  void initState() {
    super.initState();
    _name.addListener(_onChanged);
    _email.addListener(_onChanged);
    _phone.addListener(_onChanged);
    _phoneFocus.addListener(_onFocusChanged);
  }

  void _onChanged() {
    widget.controller.clearError();
    setState(() {}); // recompute button state silently — no error while typing
  }

  void _onFocusChanged() {
    if (!_phoneFocus.hasFocus && _phone.text.isNotEmpty && !_touched) {
      setState(
        () => _touched = true,
      ); // ui-checklist: signal after loss of focus
    } else if (_phoneFocus.hasFocus && _touched) {
      setState(() => _touched = false); // default state returns on re-attempt
    }
  }

  bool get _validName => isValidUserName(_name.text);
  bool get _validEmail => isValidUserEmail(_email.text);
  bool get _validPhone => isValidIndianPhone(_phone.text);
  bool get _valid => _validName && _validEmail && _validPhone;

  /// Donor's 2px colored focus ring — our brand teal (blue stays link-only;
  /// enabled/error borders ride the theme's token borders).
  InputBorder get _focusRing => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AuthTokens.radius),
        borderSide: const BorderSide(color: AuthTokens.teal, width: 2),
      );

  String? get _nameError =>
      (_touched && !_validName) ? authStringsHi['nameError'] : null;
  String? get _emailError =>
      (_touched && !_validEmail) ? authStringsHi['emailError'] : null;
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
        .slideY(begin: begin, end: 0, duration: 300.ms, curve: Curves.easeOut);
  }

  Future<void> _submit() async {
    setState(() => _touched = true);
    if (!_valid) {
      // a11y-6: focus lands on the first invalid field.
      if (!_validName) {
        _nameFocus.requestFocus();
      } else if (!_validEmail) {
        _emailFocus.requestFocus();
      } else {
        _phoneFocus.requestFocus();
      }
      return;
    }
    FocusScope.of(context).unfocus();
    await widget.controller
        .registerNameNumber(_name.text, _email.text, _phone.text);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
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
              // Welcome band (donor hero): white sheet on the slate ground
              // with the brand mark, w900 wordmark, trust line and the real
              // fact chips centered — no invented claims, no gradients.
              _rise(
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AuthTokens.surface,
                    border: Border.all(color: AuthTokens.border),
                    borderRadius: BorderRadius.circular(AuthTokens.radius),
                  ),
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/logo.png',
                        height: 84,
                        cacheWidth: 168,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: AuthTokens.tealTint,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.water_drop,
                            color: AuthTokens.teal,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Shodasha',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          color: AuthTokens.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        authStringsHi['trustLine']!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AuthTokens.muted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          Chip(
                            avatar: Icon(Icons.payments_outlined, size: 16),
                            label: Text('UPI + COD'),
                          ),
                          Chip(
                            avatar: Icon(Icons.support_agent_outlined, size: 16),
                            label: Text('WhatsApp par madad'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                begin: -0.2,
              ),
              const SizedBox(height: 24),
              // Editorial header rhythm shared with the 031 home reskin:
              // eyebrow → w900 headline → muted sub.
              const Text(
                'Naam + Email + Mobile number',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: AuthTokens.muted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                authStringsHi['registerTitle']!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: AuthTokens.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                authStringsHi['registerSubtitle']!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AuthTokens.muted,
                ),
              ),
              const SizedBox(height: 24),
              // Name — label above the field (donor), hint in-field, theme
              // borders; focus rides the brand teal.
              Text(authStringsHi['nameLabel']!, style: _fieldLabel),
              const SizedBox(height: 8),
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
                  hintText: authStringsHi['nameHint'],
                  counterText: '',
                  focusedBorder: _focusRing,
                  errorText: _nameError,
                  errorStyle: TextStyle(color: errorColor, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              Text(authStringsHi['emailLabel']!, style: _fieldLabel),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 16, color: AuthTokens.text),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _emailFocus.nextFocus(),
                decoration: InputDecoration(
                  hintText: authStringsHi['emailHint'],
                  focusedBorder: _focusRing,
                  errorText: _emailError,
                  errorStyle: TextStyle(color: errorColor, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              Text(authStringsHi['phoneLabel']!, style: _fieldLabel),
              const SizedBox(height: 8),
              TextField(
                controller: _phone,
                focusNode: _phoneFocus,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 16, color: AuthTokens.text),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: authStringsHi['phoneHint'],
                  helperText: authStringsHi['phoneHelper'],
                  helperStyle: const TextStyle(color: AuthTokens.muted),
                  // Donor prefix block: bold +91 with a hairline divider.
                  // Their flag emoji is dropped — zero-emoji law.
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 12, right: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '+91 ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AuthTokens.text,
                          ),
                        ),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          indent: 14,
                          endIndent: 14,
                          color: AuthTokens.border,
                        ),
                      ],
                    ),
                  ),
                  focusedBorder: _focusRing,
                  errorText: _phoneError,
                  errorStyle: TextStyle(color: errorColor, fontSize: 13),
                ),
              ),
              const SizedBox(height: 18),
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
                        // Donor CTA: flat, zero-elevation 52dp full-width bar
                        // (law floor 48dp holds).
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            // WHY: disabled until valid (no dead taps, no spam register).
                            onPressed: (!_valid || registering)
                                ? null
                                : _submit,
                            style: ElevatedButton.styleFrom(
                              // Locked spec: primary = black ink (green stays
                              // money-CTA-only, blue is links); donor's dark
                              // flat CTA is the same #0F172A value.
                              backgroundColor: AuthTokens.text,
                              foregroundColor: AuthTokens.bg,
                              disabledBackgroundColor: AuthTokens.text
                                  .withValues(alpha: 0.3),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AuthTokens.radius,
                                ),
                              ),
                            ),
                            child: registering
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
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
                    builder: (_) =>
                        UserDemoSheet(controller: widget.controller),
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
                  style: const TextStyle(fontSize: 12, color: AuthTokens.muted),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Madad chahiye? $kSupportPhone',
                  style: const TextStyle(fontSize: 12, color: AuthTokens.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
