// Customer sign-in / create-account screen (034).
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
import '../../core/constants/app_constants.dart';
import 'auth_controller.dart';
import 'demo_sheet.dart';

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
    if (_submitting) return;
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
        _localNotice = authStringsHi['accountExists'];
      });
      return;
    }

    setState(() => _submitting = false);
    if (_auth.rateLimitSecondsRemaining > 0) _startRateTimer();
  }

  void _openDemo() {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => UserDemoSheet(controller: _auth),
    );
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
          style: TextStyle(fontWeight: FontWeight.w900),
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
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
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: viewInsets + 24),
          child: Column(
            children: [
              _hero(),
              if (widget.notice != null)
                _banner(widget.notice!, tone: _BannerTone.warning),
              if (_localNotice != null)
                _banner(_localNotice!, tone: _BannerTone.info),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
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
    );
  }

  Widget _formBody() {
    final create = _mode == _AuthMode.create;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          create
              ? authStringsHi['createTitle']!
              : authStringsHi['signInTitle']!,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          create
              ? authStringsHi['createSubtitle']!
              : authStringsHi['signInSubtitle']!,
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        if (create) ...[
          _label(authStringsHi['nameLabel']!),
          TextFormField(
            controller: _name,
            enabled: !_submitting,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
            decoration: _decoration(
              hint: authStringsHi['nameHint']!,
              icon: Icons.person_outline,
            ),
            validator: (value) => isValidUserName(value ?? '')
                ? null
                : authStringsHi['nameError'],
          ),
          const SizedBox(height: 14),
          _label(authStringsHi['emailLabel']!),
          TextFormField(
            controller: _email,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
            decoration: _decoration(
              hint: authStringsHi['emailHint']!,
              icon: Icons.mail_outline,
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return null; // optional contact field
              return isValidUserEmail(text)
                  ? null
                  : authStringsHi['emailError'];
            },
          ),
          const SizedBox(height: 14),
        ],
        _label(authStringsHi['phoneLabel']!),
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
          style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
          decoration: _decoration(
            hint: authStringsHi['phoneHint']!,
            prefix: _phonePrefix(),
          ),
          onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
          validator: (value) => isValidIndianPhone(value ?? '')
              ? null
              : authStringsHi['phoneError'],
        ),
        const SizedBox(height: 6),
        Text(
          authStringsHi['phoneHelper']!,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        _label(authStringsHi['passwordLabel']!),
        TextFormField(
          controller: _password,
          focusNode: _passwordFocus,
          enabled: !_submitting,
          obscureText: !_showPassword,
          textInputAction: create ? TextInputAction.next : TextInputAction.done,
          autofillHints: [
            create ? AutofillHints.newPassword : AutofillHints.password,
          ],
          style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
          decoration: _decoration(
            hint: authStringsHi['passwordHint']!,
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
                  : authStringsHi['passwordError'];
            }
            return (value ?? '').isEmpty
                ? authStringsHi['passwordRequired']
                : null;
          },
        ),
        if (create) ...[
          const SizedBox(height: 14),
          _label(authStringsHi['confirmLabel']!),
          TextFormField(
            controller: _confirm,
            focusNode: _confirmFocus,
            enabled: !_submitting,
            obscureText: !_showConfirm,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
            decoration: _decoration(
              hint: authStringsHi['confirmLabel']!,
              icon: Icons.lock_reset_outlined,
              suffix: _visibilityToggle(
                visible: _showConfirm,
                onTap: () => setState(() => _showConfirm = !_showConfirm),
              ),
            ),
            onFieldSubmitted: (_) => _submit(),
            validator: (value) {
              if ((value ?? '').isEmpty) return authStringsHi['confirmError'];
              return value == _password.text
                  ? null
                  : authStringsHi['confirmError'];
            },
          ),
        ],
        const SizedBox(height: 10),
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
                authStringsHi['forgotPassword']!,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        _errorPanel(),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              disabledBackgroundColor: const Color(0xFF99F6E4),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.textOnPrimary,
                    ),
                  )
                : Text(
                    create
                        ? authStringsHi['createGo']!
                        : authStringsHi['signInGo']!,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textOnPrimary,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _submitting
                ? null
                : () =>
                      _switchMode(create ? _AuthMode.signIn : _AuthMode.create),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(
              create
                  ? authStringsHi['alreadyHere']!
                  : authStringsHi['newHere']!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ),
        if (!create) ...[
          Center(
            child: TextButton(
              onPressed: _submitting ? null : _openDemo,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(
                authStringsHi['demoLogin']!,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          const Center(
            child: Text(
              'Shodasha customer app • Password protected',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
            ),
          ),
        ] else ...[
          const SizedBox(height: 2),
          const Center(
            child: Text(
              'By creating an account, you agree to Shodasha Terms & '
              'Privacy Policy.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: Color(0xFF94A3B8),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _hero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 18, bottom: 22, left: 20, right: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F5E9), Color(0xFFDCFCE7)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      child: Column(
        children: [
          Image.asset(
            'assets/images/login_hero.jpg',
            height: 170,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox(
              height: 130,
              child: Icon(
                Icons.water_drop_rounded,
                size: 80,
                color: AppColors.money,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'SHODASHA MINERAL\nWATER SERVICE',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: Color(0xFF14532D),
              letterSpacing: 0.8,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pure 20L mineral water delivered directly to your doorstep',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Color(0xFF1E293B),
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
      hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
      prefixIcon:
          prefix ??
          (icon == null
              ? null
              : Icon(icon, size: 20, color: AppColors.textSecondary)),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      errorStyle: const TextStyle(fontSize: 11.5, height: 1.3),
    );
  }

  Widget _phonePrefix() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+91',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(width: 8),
          VerticalDivider(
            width: 1,
            thickness: 1,
            indent: 14,
            endIndent: 14,
            color: Color(0xFFCBD5E1),
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
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _errorPanel() {
    final message = _auth.errorMessage;
    if (message == null) return const SizedBox.shrink();
    final wait = _auth.rateLimitSecondsRemaining;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 18, color: Color(0xFFB91C1C)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Color(0xFF7F1D1D),
                    ),
                  ),
                  if (wait > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Try again in ${wait}s.',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF7F1D1D),
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
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: warning ? const Color(0xFFFEF9C3) : const Color(0xFFE0F2FE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: warning ? const Color(0xFFFDE047) : const Color(0xFFBAE6FD),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              warning ? Icons.info_outline : Icons.check_circle_outline,
              size: 18,
              color: warning
                  ? const Color(0xFF854D0E)
                  : const Color(0xFF0369A1),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: warning
                      ? const Color(0xFF713F12)
                      : const Color(0xFF075985),
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
