// Customer sign-in / create-account screen (034, unslop 037).
//
// Password auth only. This screen never calls the retired customer auth
// routes. Sign in is the default; create account is an internal mode.
// Validation, busy, 401/409/422/429, offline and 5xx states all
// live here, and duplicate signup pivots to sign-in without claiming the row.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';

import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import 'auth_controller.dart';

enum _AuthMode { signIn, create }

class DonorLoginScreen extends StatefulWidget {
  const DonorLoginScreen({super.key, required this.controller, this.notice});

  final AuthController controller;
  final String? notice;

  @override
  State<DonorLoginScreen> createState() => _DonorLoginScreenState();
}

class _DonorLoginScreenState extends State<DonorLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  _AuthMode _mode = _AuthMode.signIn;
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _submitting = false;
  String? _localNotice;
  Timer? _rateTimer;

  AuthController get _auth => widget.controller;

  @override
  void initState() {
    super.initState();
    if (_auth.rateLimitSecondsRemaining > 0) _startRateTimer();
  }

  @override
  void dispose() {
    _rateTimer?.cancel();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _startRateTimer() {
    _rateTimer?.cancel();
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_auth.rateLimitSecondsRemaining <= 0) {
        timer.cancel();
      }
      setState(() {});
    });
  }

  void _switchMode(_AuthMode mode) {
    if (_submitting) return;
    _auth.clearError();
    setState(() {
      _mode = mode;
      _localNotice = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting || _auth.rateLimitSecondsRemaining > 0) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _localNotice = null;
    });
    _auth.clearError();

    final ok = _mode == _AuthMode.signIn
        ? await _auth.login(rawPhone: _phone.text, password: _password.text)
        : await _auth.register(
            name: _name.text,
            email: _email.text,
            rawPhone: _phone.text,
            password: _password.text,
            confirmPassword: _confirm.text,
          );
    if (!mounted) return;

    if (ok) {
      // AuthGate swaps to the shell on the controller notification.
      setState(() => _submitting = false);
      return;
    }

    if (_auth.lastErrorCode == 'ACCOUNT_EXISTS') {
      _auth.clearError();
      setState(() {
        _mode = _AuthMode.signIn;
        _submitting = false;
        _showPassword = false;
        _localNotice = authStrings['accountExists'];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passwordFocus.requestFocus();
      });
      return;
    }

    setState(() => _submitting = false);
    if (_auth.rateLimitSecondsRemaining > 0) _startRateTimer();
  }

  Future<void> _openSupport() async {
    final digits = kSupportPhone.replaceAll(RegExp(r'\D'), '');
    final call = Uri(scheme: 'tel', path: digits);
    final whatsapp = Uri.parse('https://wa.me/$digits');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Forgot password?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'For your safety, password resets are handled by Shodasha support. '
          'Call or WhatsApp us and we will verify your account and set a new '
          'password.',
          style: TextStyle(fontSize: 14, height: 1.4),
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
            child: const Text('Call support'),
          ),
        ],
      ),
    );
  }

  Future<void> _launch(Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Could not open the app. Support: $kSupportPhone'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: ShodashaTheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: viewInsets + 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
              child: Column(
                children: [
                  _hero(),
                  if (widget.notice != null)
                    _banner(widget.notice!, tone: _BannerTone.warning),
                  if (_localNotice != null)
                    _banner(_localNotice!, tone: _BannerTone.info),
                  const SizedBox(height: AppSpacing.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: AutofillGroup(child: _formBody()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formBody() {
    final create = _mode == _AuthMode.create;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          create ? authStrings['createTitle']! : authStrings['signInTitle']!,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: ShodashaTheme.ink,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          create
              ? authStrings['createSubtitle']!
              : authStrings['signInSubtitle']!,
          style: const TextStyle(
            fontSize: 14,
            height: 1.4,
            color: ShodashaTheme.muted,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (create) ...[
          _label(authStrings['nameLabel']!),
          TextFormField(
            controller: _name,
            enabled: !_submitting,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
            decoration: _decoration(
              hint: authStrings['nameHint']!,
              icon: Icons.person_outline,
            ),
            validator: (value) =>
                isValidUserName(value ?? '') ? null : authStrings['nameError'],
          ),
          const SizedBox(height: AppSpacing.lg),
          _label(authStrings['emailLabel']!),
          TextFormField(
            controller: _email,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
            decoration: _decoration(
              hint: authStrings['emailHint']!,
              icon: Icons.mail_outline,
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return null; // optional contact field
              return isValidUserEmail(text) ? null : authStrings['emailError'];
            },
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        _label(authStrings['phoneLabel']!),
        TextFormField(
          controller: _phone,
          enabled: !_submitting,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            LengthLimitingTextInputFormatter(16),
          ],
          style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
          decoration: _decoration(
            hint: authStrings['phoneHint']!,
            prefix: _phonePrefix(),
          ),
          onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
          validator: (value) => isValidIndianPhone(value ?? '')
              ? null
              : authStrings['phoneError'],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          authStrings['phoneHelper']!,
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: ShodashaTheme.muted,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _label(authStrings['passwordLabel']!),
        TextFormField(
          controller: _password,
          focusNode: _passwordFocus,
          enabled: !_submitting,
          obscureText: !_showPassword,
          textInputAction: create ? TextInputAction.next : TextInputAction.done,
          autofillHints: [
            create ? AutofillHints.newPassword : AutofillHints.password,
          ],
          style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
          decoration: _decoration(
            hint: authStrings['passwordHint']!,
            icon: Icons.lock_outline,
            suffix: _visibilityToggle(
              visible: _showPassword,
              onTap: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          onFieldSubmitted: (_) {
            if (create) {
              _confirmFocus.requestFocus();
            } else {
              _submit();
            }
          },
          validator: (value) {
            if (create) {
              return isValidPassword(value ?? '')
                  ? null
                  : authStrings['passwordError'];
            }
            return (value ?? '').isEmpty
                ? authStrings['passwordRequired']
                : null;
          },
        ),
        if (create) ...[
          const SizedBox(height: AppSpacing.lg),
          _label(authStrings['confirmLabel']!),
          TextFormField(
            controller: _confirm,
            focusNode: _confirmFocus,
            enabled: !_submitting,
            obscureText: !_showConfirm,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
            decoration: _decoration(
              hint: authStrings['confirmLabel']!,
              icon: Icons.lock_reset_outlined,
              suffix: _visibilityToggle(
                visible: _showConfirm,
                onTap: () => setState(() => _showConfirm = !_showConfirm),
              ),
            ),
            onFieldSubmitted: (_) => _submit(),
            validator: (value) {
              if ((value ?? '').isEmpty) return authStrings['confirmError'];
              return value == _password.text
                  ? null
                  : authStrings['confirmError'];
            },
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (!create)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _submitting ? null : _openSupport,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 6),
                minimumSize: const Size(48, 48),
              ),
              child: Text(
                authStrings['forgotPassword']!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ShodashaTheme.tealDeep,
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        _errorPanel(),
        AppButton(
          label: create ? authStrings['createGo']! : authStrings['signInGo']!,
          busy: _submitting,
          onPressed: _submit,
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: TextButton(
            onPressed: _submitting
                ? null
                : () =>
                      _switchMode(create ? _AuthMode.signIn : _AuthMode.create),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(
              create ? authStrings['alreadyHere']! : authStrings['newHere']!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ShodashaTheme.tealDeep,
              ),
            ),
          ),
        ),
        if (create) ...[
          const SizedBox(height: AppSpacing.xs),
          const Center(
            child: Text(
              'By creating an account, you agree to Shodasha Terms & '
              'Privacy Policy.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: ShodashaTheme.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _hero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ShodashaTheme.tealTint,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: ShodashaTheme.tealDark.withValues(alpha: 0.15),
              ),
            ),
            child: const Icon(
              Icons.water_drop_rounded,
              size: 34,
              color: ShodashaTheme.tealDeep,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Shodasha',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: ShodashaTheme.tealDeep,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Pure 20L water delivered to your doorstep',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: ShodashaTheme.muted,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: ShodashaTheme.bg,
              borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
              border: Border.all(color: ShodashaTheme.border),
            ),
            child: const Text(
              'RO+UV · Lab Tested · Bhopal',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ShodashaTheme.tealDeep,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
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
      prefixIcon:
          prefix ??
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
              fontWeight: FontWeight.w700,
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

  Widget _visibilityToggle({
    required bool visible,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: _submitting ? null : onTap,
      tooltip: visible ? 'Hide password' : 'Show password',
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 20,
        color: ShodashaTheme.muted,
      ),
    );
  }

  Widget _errorPanel() {
    final message = _auth.errorMessage;
    if (message == null) return const SizedBox.shrink();
    final wait = _auth.rateLimitSecondsRemaining;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: ShodashaTheme.danger.withValues(alpha: 0.06),
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
                        'Try again in $wait seconds',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
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

  Widget _banner(String message, {required _BannerTone tone}) {
    final warning = tone == _BannerTone.warning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: warning ? ShodashaTheme.solarTint : ShodashaTheme.etaTint,
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
          border: Border.all(
            color: warning
                ? ShodashaTheme.solarBorder
                : ShodashaTheme.tealDark.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              warning ? Icons.info_outline : Icons.check_circle_outline,
              size: 18,
              color: warning ? ShodashaTheme.warning : ShodashaTheme.link,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: warning ? ShodashaTheme.warning : ShodashaTheme.link,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _BannerTone { warning, info }
