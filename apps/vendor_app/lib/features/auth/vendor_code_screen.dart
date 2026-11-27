// Vendor Partner welcome & access-code login screen.
// Mirrors the Customer app's Welcome -> Sign In flow with the Shodasha Partner emblem.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart' show kSupportPhone;
import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import 'auth_controller.dart';
import 'vendor_strings.dart';

enum VendorAuthMode { welcome, signIn }

class VendorCodeScreen extends StatefulWidget {
  const VendorCodeScreen({
    super.key,
    required this.controller,
    this.initialMode,
  });

  final AuthController controller;
  final VendorAuthMode? initialMode;

  @override
  State<VendorCodeScreen> createState() => _VendorCodeScreenState();
}

class _VendorCodeScreenState extends State<VendorCodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();

  late VendorAuthMode _mode;
  bool _obscure = true;
  Timer? _rateTimer;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? VendorAuthMode.welcome;
    widget.controller.addListener(_onAuth);
    if (widget.controller.rateLimitSecondsRemaining > 0) _startRateTimer();
  }

  void _onAuth() {
    if (!mounted) return;
    if (widget.controller.rateLimitSecondsRemaining > 0 &&
        (_rateTimer == null || !_rateTimer!.isActive)) {
      _startRateTimer();
    }
    setState(() {});
  }

  void _startRateTimer() {
    _rateTimer?.cancel();
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (widget.controller.rateLimitSecondsRemaining <= 0) {
        t.cancel();
      }
      setState(() {});
    });
  }

  void _switchMode(VendorAuthMode mode) {
    if (widget.controller.status == AuthStatus.verifying) return;
    widget.controller.clearError();
    setState(() => _mode = mode);
  }

  Future<void> _submit() async {
    final c = widget.controller;
    if (c.status == AuthStatus.verifying || c.rateLimitSecondsRemaining > 0) {
      return;
    }
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await c.codeLogin(_phone.text, _code.text);
  }

  Future<void> _openSupport() async {
    final digits = kSupportPhone.replaceAll(RegExp(r'\D'), '');
    final call = Uri(scheme: 'tel', path: digits);
    final whatsapp = Uri.parse(
      'https://wa.me/$digits?text=Hello%20Admin%2C%20I%20need%20help%20logging%20into%20Shodasha%20Partner',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Need help logging in?',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'Partner access codes are issued by Shodasha Admin. '
          'Call or message us on WhatsApp if you need a new code or help signing in.',
          style: TextStyle(fontSize: 14, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _launch(whatsapp);
            },
            child: const Text('WhatsApp'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ShodashaTheme.tealDeep,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _launch(call);
            },
            child: const Text('Call Admin'),
          ),
        ],
      ),
    );
  }

  Future<void> _launch(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _rateTimer?.cancel();
    widget.controller.removeListener(_onAuth);
    _phone.dispose();
    _code.dispose();
    _phoneFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: viewInsets + AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
              child: _mode == VendorAuthMode.welcome
                  ? _buildWelcomeView()
                  : _buildFormView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner({required bool showBackButton}) {
    return Container(
      width: double.infinity,
      color: ShodashaTheme.teal,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              child: Row(
                children: [
                  if (showBackButton)
                    Semantics(
                      button: true,
                      label: 'Back',
                      child: GestureDetector(
                        onTap: () => _switchMode(VendorAuthMode.welcome),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: ShodashaTheme.bg.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                            boxShadow: ShodashaTheme.subtleCardShadow,
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 16,
                            color: ShodashaTheme.ink,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 40),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xs,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: Image.asset(
                'assets/logo.png',
                height: 200,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeView() {
    return Column(
      children: [
        _buildHeroBanner(showBackButton: false),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              Text(
                vendorStringsHi['appName']!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: ShodashaTheme.tealDeep,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                vendorStringsHi['appTagline']!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: ShodashaTheme.muted,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _switchMode(VendorAuthMode.signIn),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ShodashaTheme.teal,
                    foregroundColor: ShodashaTheme.bg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: Text(
                    vendorStringsHi['loginGo']!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: _openSupport,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: ShodashaTheme.bg,
                    foregroundColor: ShodashaTheme.tealDeep,
                    side: const BorderSide(
                      color: ShodashaTheme.teal,
                      width: 1.5,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: const Text(
                    'Need help? Contact Admin',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormView() {
    final c = widget.controller;
    final busy = c.status == AuthStatus.verifying;
    final wait = c.rateLimitSecondsRemaining;
    final rateLocked = wait > 0;

    return Column(
      children: [
        _buildHeroBanner(showBackButton: true),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vendorStringsHi['loginTitle']!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: ShodashaTheme.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    vendorStringsHi['loginSubtitle']!,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: ShodashaTheme.muted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _label(vendorStringsHi['phoneLabel']!),
                  TextFormField(
                    controller: _phone,
                    focusNode: _phoneFocus,
                    enabled: !busy && !rateLocked,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    maxLength: 10,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    style: const TextStyle(
                      fontSize: 16,
                      color: ShodashaTheme.ink,
                    ),
                    decoration: _decoration(
                      hint: vendorStringsHi['phoneHint']!,
                      prefix: _phonePrefix(),
                    ),
                    onChanged: (_) => c.clearError(),
                    onFieldSubmitted: (_) => _codeFocus.requestFocus(),
                    validator: (v) => isValidIndianPhone(v ?? '')
                        ? null
                        : vendorStringsHi['phoneError'],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _label(vendorStringsHi['codeLabel']!),
                  TextFormField(
                    controller: _code,
                    focusNode: _codeFocus,
                    enabled: !busy && !rateLocked,
                    obscureText: _obscure,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    maxLength: 32,
                    style: const TextStyle(
                      fontSize: 16,
                      color: ShodashaTheme.ink,
                    ),
                    decoration: _decoration(
                      hint: vendorStringsHi['codeHint']!,
                      icon: Icons.lock_outline,
                      suffix: IconButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => _obscure = !_obscure),
                        tooltip: _obscure ? 'Show code' : 'Hide code',
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: ShodashaTheme.muted,
                        ),
                      ),
                    ),
                    onChanged: (_) => c.clearError(),
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) => isValidAccessCode(v ?? '')
                        ? null
                        : vendorStringsHi['codeError'],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: busy ? null : _openSupport,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        minimumSize: const Size(48, 48),
                      ),
                      child: const Text(
                        'Need help? Contact Admin',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ShodashaTheme.tealDeep,
                        ),
                      ),
                    ),
                  ),
                  if (c.errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _errorPanel(c.errorMessage!, wait: wait),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: busy
                        ? vendorStringsHi['loggingIn']!
                        : vendorStringsHi['loginGo']!,
                    kind: AppButtonKind.primary,
                    busy: busy,
                    onPressed: (busy || rateLocked) ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ShodashaTheme.ink,
          ),
        ),
      );

  InputDecoration _decoration({
    required String hint,
    IconData? icon,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: ShodashaTheme.muted),
      counterText: '',
      prefixIcon: prefix ??
          (icon == null
              ? null
              : Icon(icon, size: 20, color: ShodashaTheme.muted)),
      suffixIcon: suffix,
      filled: true,
      fillColor: ShodashaTheme.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.tealDark, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        borderSide: const BorderSide(color: ShodashaTheme.danger, width: 2),
      ),
      errorStyle: const TextStyle(fontSize: 12, height: 1.35),
    );
  }

  Widget _phonePrefix() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+91',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: ShodashaTheme.ink,
            ),
          ),
          SizedBox(width: 8),
          VerticalDivider(
            width: 1,
            thickness: 1,
            indent: 14,
            endIndent: 14,
            color: ShodashaTheme.border,
          ),
        ],
      ),
    );
  }

  Widget _errorPanel(String message, {required int wait}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: ShodashaTheme.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
          border: Border.all(
            color: ShodashaTheme.danger.withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline,
              size: 18,
              color: ShodashaTheme.danger,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: ShodashaTheme.danger,
                    ),
                  ),
                  if (wait > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        wait >= 60
                            ? 'Try again in ${(wait ~/ 60).toString().padLeft(2, '0')}:${(wait % 60).toString().padLeft(2, '0')}'
                            : 'Try again in $wait seconds',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ShodashaTheme.danger,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
