import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.api,
    required this.onLoginSuccess,
  });

  final ApiClient api;
  final VoidCallback onLoginSuccess;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _errorMessage;
  DateTime? _rateLimitUntil;
  int _rateLimitStrikes = 0;
  Timer? _rateTimer;

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

  @override
  void dispose() {
    _rateTimer?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _rateLimitSecondsRemaining > 0) return;
    final name = _nameController.text.trim();
    final rawPhone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final code = _codeController.text.trim();

    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your name');
      return;
    }
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(rawPhone)) {
      setState(() => _errorMessage = 'Enter a valid 10-digit mobile number (starting 6–9)');
      return;
    }
    if (code.length < 4) {
      setState(() => _errorMessage =
          'Enter the sign-in code your vendor gave you');
      return;
    }

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
            _errorMessage = 'Too many attempts — please wait before trying again.';
          } else {
            _errorMessage = e.toString().replaceFirst('Exception: ', '');
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wait = _rateLimitSecondsRemaining;
    final rateLocked = wait > 0;
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Rider App Logo
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ShodashaTheme.border),
                      boxShadow: const [ShodashaTheme.subtleCardShadow],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Title & Subtitle
                const Text(
                  'Shodasha Rider',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Doorstep Delivery & OTP Verification',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: ShodashaTheme.muted,
                  ),
                ),

                const SizedBox(height: AppSpacing.xxl),

                // Name Input
                const Text(
                  'Your Name',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _nameController,
                  enabled: !_busy && !rateLocked,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'e.g. Ramesh Kumar',
                    filled: true,
                    fillColor: ShodashaTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                      borderSide: const BorderSide(color: ShodashaTheme.border),
                    ),
                    prefixIcon: const Icon(Icons.person_outline_rounded, color: ShodashaTheme.muted),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // Phone Input
                const Text(
                  'Mobile Number',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _phoneController,
                  enabled: !_busy && !rateLocked,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: '10-digit registered number',
                    counterText: '',
                    filled: true,
                    fillColor: ShodashaTheme.surface,
                    prefixText: '+91 ',
                    prefixStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ShodashaTheme.ink,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                      borderSide: const BorderSide(color: ShodashaTheme.border),
                    ),
                    prefixIcon: const Icon(Icons.phone_outlined, color: ShodashaTheme.muted),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // Vendor-issued sign-in code (password equivalent)
                const Text(
                  'Sign-in Code',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _codeController,
                  enabled: !_busy && !rateLocked,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 2),
                  decoration: InputDecoration(
                    hintText: '6-digit code from your vendor',
                    counterText: '',
                    filled: true,
                    fillColor: ShodashaTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                      borderSide: const BorderSide(color: ShodashaTheme.border),
                    ),
                    prefixIcon: const Icon(Icons.password_rounded, color: ShodashaTheme.muted),
                  ),
                ),

                // Error Notice
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: ShodashaTheme.dangerTint,
                      borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                      border: Border.all(color: ShodashaTheme.danger.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: ShodashaTheme.danger, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: ShodashaTheme.dangerDark,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (rateLocked) ...[
                                const SizedBox(height: 4),
                                Text(
                                  wait >= 60
                                      ? 'Try again in ${(wait ~/ 60).toString().padLeft(2, '0')}:${(wait % 60).toString().padLeft(2, '0')}'
                                      : 'Try again in $wait seconds',
                                  style: const TextStyle(
                                    color: ShodashaTheme.dangerDark,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.xl),

                // Submit CTA
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
    );
  }
}

