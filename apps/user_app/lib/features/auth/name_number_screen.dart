// S2 — Register screen: name + @gmail.com email + 10-digit mobile, built on
// the donor login grammar (hero image, welcome band, white form card, flat
// ink CTA). No OTP anywhere.
//
// Ported behavior from the legacy name_number_screen (source of truth):
// validators + controller bindings + error mapping are untouched; guest
// browsing keeps prices open; the demo door stays server-gated and errors
// honestly (never a local success). Copy for the new chrome is donor
// English; the controller's validation/error strings stay verbatim.
//
// States.md covered: form default/focused/filled/invalid/submitting/failed/
// success; auth guest/authenticated; network + server errors; disabled demo
// (server-closed); empty guidance. Green is money-only → this CTA is ink.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart' show kSupportPhone;
import '../../core/theme.dart';
import 'auth_controller.dart';
import 'demo_sheet.dart';

const TextStyle _labelStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w800,
  color: ShodashaTheme.ink,
);

const TextStyle _eyebrowStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w800,
  letterSpacing: 0.4,
  color: ShodashaTheme.muted,
);

/// Name + gmail + mobile entry. [onGuestBrowse] keeps prices visible WITHOUT
/// login (user-flows flow 1); [onRegistered] lets a pushed route close on
/// success (see [openRegister] in auth_gate.dart) — null when embedded in
/// the gate, which swaps itself to home on the controller notification.
class NameNumberScreen extends StatefulWidget {
  const NameNumberScreen({
    super.key,
    required this.controller,
    this.onGuestBrowse,
    this.onRegistered,
  });

  final AuthController controller;
  final VoidCallback? onGuestBrowse;
  final VoidCallback? onRegistered;

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
      setState(() => _touched = true); // signal after loss of focus
    } else if (_phoneFocus.hasFocus && _touched) {
      setState(() => _touched = false); // default state returns on re-attempt
    }
  }

  bool get _validName => isValidUserName(_name.text);
  bool get _validEmail => isValidUserEmail(_email.text);
  bool get _validPhone => isValidIndianPhone(_phone.text);
  bool get _valid => _validName && _validEmail && _validPhone;

  /// Donor's 2px teal focus ring (blue stays link-only).
  InputBorder get _focusRing => OutlineInputBorder(
    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
    borderSide: const BorderSide(color: ShodashaTheme.teal, width: 2),
  );

  String? get _nameError =>
      (_touched && !_validName) ? authStringsHi['nameError'] : null;
  String? get _emailError =>
      (_touched && !_validEmail) ? authStringsHi['emailError'] : null;
  String? get _phoneError =>
      (_touched && !_validPhone) ? authStringsHi['phoneError'] : null;

  Future<void> _submit() async {
    setState(() => _touched = true);
    if (!_valid) {
      // a11y: focus lands on the first invalid field.
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
    final ok = await widget.controller.registerNameNumber(
      _name.text,
      _email.text,
      _phone.text,
    );
    if (ok && mounted) widget.onRegistered?.call();
  }

  Future<void> _openDemo() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ShodashaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusSheet),
        ),
      ),
      builder: (_) => UserDemoSheet(controller: widget.controller),
    );
    if (ok == true && mounted) widget.onRegistered?.call();
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
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            children: [
              _heroBand(),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _formCard(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Donor hero + welcome band, flattened per the no-gradient law: the
  /// photo sits on a teal tint band with the wordmark, one honest trust
  /// line and two capability chips (no invented prices).
  Widget _heroBand() {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: ShodashaTheme.tealTint,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(ShodashaTheme.radiusSheet),
        ),
      ),
      child: Column(
        children: [
          Image.asset(
            'assets/images/login_hero.png',
            height: 190,
            width: double.infinity,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            cacheWidth: 900,
            errorBuilder: (_, _, _) => const SizedBox(
              height: 190,
              child: Center(
                child: Icon(
                  Icons.water_drop_rounded,
                  size: 72,
                  color: ShodashaTheme.teal,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              children: [
                const Text(
                  'MINERAL WATER SERVICE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: ShodashaTheme.tealDeep,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Shodasha',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: ShodashaTheme.ink,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Pure 20L mineral water delivered directly to your '
                  'doorstep in Bhopal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: ShodashaTheme.tealDeep,
                  ),
                ),
                const SizedBox(height: 12),
                const Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FactChip(
                      icon: Icons.payments_outlined,
                      label: 'UPI + COD',
                    ),
                    _FactChip(
                      icon: Icons.support_agent_outlined,
                      label: 'WhatsApp support',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('NEW ACCOUNT', style: _eyebrowStyle),
          const SizedBox(height: 6),
          const Text(
            'Create your account',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: ShodashaTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No OTP. Just your name, Gmail address and mobile number.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: ShodashaTheme.muted,
            ),
          ),
          const SizedBox(height: 20),
          Text('Name', style: _labelStyle),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            focusNode: _nameFocus,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            maxLength: 100,
            // WHY: 16px stops iOS auto-zoom (mobile-native §4).
            style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _emailFocus.requestFocus(),
            decoration: InputDecoration(
              hintText: 'Your name',
              counterText: '',
              focusedBorder: _focusRing,
              errorText: _nameError,
              errorStyle: const TextStyle(
                color: ShodashaTheme.danger,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Email', style: _labelStyle),
          const SizedBox(height: 8),
          TextField(
            controller: _email,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _phoneFocus.requestFocus(),
            decoration: InputDecoration(
              hintText: 'you@gmail.com',
              focusedBorder: _focusRing,
              errorText: _emailError,
              errorStyle: const TextStyle(
                color: ShodashaTheme.danger,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Mobile Number', style: _labelStyle),
          const SizedBox(height: 8),
          TextField(
            controller: _phone,
            focusNode: _phoneFocus,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Enter 10-digit mobile number',
              helperText: 'Only 10 digits, starting with 6–9.',
              helperStyle: const TextStyle(color: ShodashaTheme.muted),
              // Donor prefix block: bold +91 with a hairline divider
              // (their flag emoji is dropped — zero-emoji law).
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
                        color: ShodashaTheme.ink,
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      indent: 14,
                      endIndent: 14,
                      color: ShodashaTheme.border,
                    ),
                  ],
                ),
              ),
              focusedBorder: _focusRing,
              errorText: _phoneError,
              errorStyle: const TextStyle(
                color: ShodashaTheme.danger,
                fontSize: 13,
              ),
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
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      // WHY: disabled until valid (no dead taps, no spam
                      // register); disabled again while the call is in flight.
                      onPressed: (!_valid || registering) ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        // Ink = this screen's primary (green is money-only,
                        // blue is links); donor's dark flat CTA.
                        backgroundColor: ShodashaTheme.ink,
                        foregroundColor: ShodashaTheme.bg,
                        disabledBackgroundColor: ShodashaTheme.ink.withValues(
                          alpha: 0.3,
                        ),
                        disabledForegroundColor: ShodashaTheme.surface,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            ShodashaTheme.radius,
                          ),
                        ),
                      ),
                      child: registering
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: ShodashaTheme.surface,
                              ),
                            )
                          : const Text('Create Account'),
                    ),
                  ),
                  if (registering)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Creating your account…',
                        style: TextStyle(
                          fontSize: 13,
                          color: ShodashaTheme.muted,
                        ),
                      ),
                    ),
                  if (apiError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 16,
                            color: ShodashaTheme.danger,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              apiError,
                              style: const TextStyle(
                                color: ShodashaTheme.danger,
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
          const SizedBox(height: 12),
          if (widget.onGuestBrowse != null)
            Center(
              child: TextButton(
                onPressed: widget.onGuestBrowse,
                style: TextButton.styleFrom(
                  foregroundColor: ShodashaTheme.blue,
                  minimumSize: const Size(48, ShodashaTheme.minTarget),
                ),
                child: const Text('Browse without an account'),
              ),
            ),
          Center(
            child: TextButton(
              onPressed: _openDemo,
              style: TextButton.styleFrom(
                foregroundColor: ShodashaTheme.blue,
                minimumSize: const Size(48, ShodashaTheme.minTarget),
              ),
              child: const Text('Try the demo account'),
            ),
          ),
          const Center(
            child: Text(
              'Prices never need a login.',
              style: TextStyle(fontSize: 12, color: ShodashaTheme.muted),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Need help? $kSupportPhone',
              style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Non-interactive capability pill on the welcome band.
class _FactChip extends StatelessWidget {
  const _FactChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: ShodashaTheme.teal),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ShodashaTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}
