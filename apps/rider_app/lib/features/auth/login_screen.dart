// Rider welcome & sign-in screen.
// Mirrors the Customer app's Welcome -> Sign In flow with the Shodasha Rider emblem.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';

enum RiderAuthMode { welcome, signIn }

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.api,
    required this.onLoginSuccess,
    this.initialMode,
  });

  final ApiClient api;
  final VoidCallback onLoginSuccess;
  final RiderAuthMode? initialMode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();

  late RiderAuthMode _mode;
  bool _obscureCode = true;
  bool _busy = false;
  String? _errorMessage;
  DateTime? _rateLimitUntil;
  int _rateLimitStrikes = 0;
  Timer? _rateTimer;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? RiderAuthMode.welcome;
  }

  int get _rateLimitSecondsRemaining {
    final until = _rateLimitUntil;
    if (until == null) return 0;
    final ms = until.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  void _startRateTimer() {
    _rateTimer?.cancel();
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_rateLimitSecondsRemaining <= 0) {
        t.cancel();
      }
      setState(() {});
    });
  }

  void _switchMode(RiderAuthMode mode) {
    if (_busy) return;
    setState(() {
      _mode = mode;
      _errorMessage = null;
    });
  }

  @override
  void dispose() {
    _rateTimer?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _phoneFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _rateLimitSecondsRemaining > 0) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _nameController.text.trim();
    final rawPhone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final code = _codeController.text.trim();

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      await widget.api.loginRider(
        phone: rawPhone,
        name: name,
        code: code,
      );
      _rateLimitStrikes = 0;
      _rateLimitUntil = null;
      if (mounted) {
        widget.onLoginSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          if (e is ApiException && e.statusCode == 429) {
            _rateLimitStrikes++;
            final gradual = 60 * (1 << (_rateLimitStrikes - 1).clamp(0, 5));
            final serverWait = e.retryAfterSeconds ?? 60;
            final wait = (serverWait > gradual ? serverWait : gradual).clamp(60, 1800);
            _rateLimitUntil = DateTime.now().add(Duration(seconds: wait));
            _startRateTimer();
            _errorMessage = 'Too many attempts — please wait before trying again';
          } else {
            _errorMessage = e.toString().replaceFirst('Exception: ', '');
          }
        });
      }
    }
  }

  Future<void> _openHelp() async {
    const supportPhone = '+91 93021 90067';
    final digits = supportPhone.replaceAll(RegExp(r'\D'), '');
    final call = Uri(scheme: 'tel', path: digits);
    final whatsapp = Uri.parse(
      'https://wa.me/$digits?text=Hello%2C%20I%20need%20help%20logging%20into%20Shodasha%20Rider',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Need your sign-in code?',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'Your 6-digit sign-in code is created by your vendor. '
          'Ask your vendor for your code, or contact Shodasha support for help.',
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
            child: const Text('Call support'),
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
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: ShodashaTheme.surface,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: viewInsets + AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _mode == RiderAuthMode.welcome
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
                        onTap: () => _switchMode(RiderAuthMode.welcome),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: ShodashaTheme.surface.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                            boxShadow: const [ShodashaTheme.subtleCardShadow],
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
              const Text(
                'Shodasha Rider',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: ShodashaTheme.tealDeep,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'View your daily delivery stops, collect cash, and verify customer OTPs',
                textAlign: TextAlign.center,
                style: TextStyle(
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
                  onPressed: () => _switchMode(RiderAuthMode.signIn),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ShodashaTheme.teal,
                    foregroundColor: ShodashaTheme.surface,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: const Text(
                    'Login',
                    style: TextStyle(
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
                  onPressed: _openHelp,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: ShodashaTheme.surface,
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
                    'Need your sign-in code?',
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
    final wait = _rateLimitSecondsRemaining;
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
                  const Text(
                    'Sign in to Rider',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: ShodashaTheme.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Enter your name, mobile number, and the code from your vendor',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: ShodashaTheme.muted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _label('Your Name'),
                  TextFormField(
                    controller: _nameController,
                    enabled: !_busy && !rateLocked,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    style: const TextStyle(
                      fontSize: 16,
                      color: ShodashaTheme.ink,
                    ),
                    decoration: _decoration(
                      hint: 'e.g. Ramesh Kumar',
                      icon: Icons.person_outline_rounded,
                    ),
                    onChanged: (_) {
                      if (_errorMessage != null) setState(() => _errorMessage = null);
                    },
                    onFieldSubmitted: (_) => _phoneFocus.requestFocus(),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Please enter your name' : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _label('Mobile Number'),
                  TextFormField(
                    controller: _phoneController,
                    focusNode: _phoneFocus,
                    enabled: !_busy && !rateLocked,
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
                      hint: '10-digit registered number',
                      prefix: _phonePrefix(),
                    ),
                    onChanged: (_) {
                      if (_errorMessage != null) setState(() => _errorMessage = null);
                    },
                    onFieldSubmitted: (_) => _codeFocus.requestFocus(),
                    validator: (v) {
                      final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                      return RegExp(r'^[6-9]\d{9}$').hasMatch(digits)
                          ? null
                          : 'Enter a valid 10-digit mobile number (starting 6–9)';
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _label('Sign-in Code'),
                  TextFormField(
                    controller: _codeController,
                    focusNode: _codeFocus,
                    enabled: !_busy && !rateLocked,
                    obscureText: _obscureCode,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: 8,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    style: const TextStyle(
                      fontSize: 16,
                      color: ShodashaTheme.ink,
                    ),
                    decoration: _decoration(
                      hint: '6-digit code from your vendor',
                      icon: Icons.lock_outline,
                      suffix: IconButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _obscureCode = !_obscureCode),
                        tooltip: _obscureCode ? 'Show code' : 'Hide code',
                        icon: Icon(
                          _obscureCode
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: ShodashaTheme.muted,
                        ),
                      ),
                    ),
                    onChanged: (_) {
                      if (_errorMessage != null) setState(() => _errorMessage = null);
                    },
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) => (v ?? '').trim().length < 4
                        ? 'Enter the sign-in code your vendor gave you'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy ? null : _openHelp,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        minimumSize: const Size(48, 48),
                      ),
                      child: const Text(
                        'Need your sign-in code?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ShodashaTheme.tealDeep,
                        ),
                      ),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _errorPanel(_errorMessage!, wait: wait),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: rateLocked
                        ? 'Wait ${(wait ~/ 60).toString().padLeft(2, '0')}:${(wait % 60).toString().padLeft(2, '0')}'
                        : 'Start Delivery Shift',
                    icon: Icons.two_wheeler_rounded,
                    busy: _busy,
                    onPressed: (_busy || rateLocked) ? null : _submit,
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
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
        borderSide: const BorderSide(color: ShodashaTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
        borderSide: const BorderSide(color: ShodashaTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
        borderSide: const BorderSide(color: ShodashaTheme.tealDark, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
        borderSide: const BorderSide(color: ShodashaTheme.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
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
          color: ShodashaTheme.dangerTint,
          borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
          border: Border.all(color: ShodashaTheme.danger.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: ShodashaTheme.danger,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: const TextStyle(
                      color: ShodashaTheme.dangerDark,
                      fontSize: 13,
                      height: 1.4,
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
                          color: ShodashaTheme.dangerDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
