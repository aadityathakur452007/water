import 'package:flutter/material.dart';
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
  bool _busy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final rawPhone = _phoneController.text.replaceAll(RegExp(r'\D'), '');

    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your name');
      return;
    }
    if (rawPhone.length < 10) {
      setState(() => _errorMessage = 'Enter a valid 10-digit mobile number');
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
      );
      if (mounted) {
        widget.onLoginSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                // Cane Emblem
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: ShodashaTheme.tealTint,
                      shape: BoxShape.circle,
                      border: Border.all(color: ShodashaTheme.teal.withValues(alpha: 0.3), width: 2),
                    ),
                    child: const Icon(
                      Icons.water_drop_rounded,
                      size: 40,
                      color: ShodashaTheme.teal,
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
                    fontWeight: FontWeight.w900,
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
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
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
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: ShodashaTheme.dangerDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.xl),

                // Submit CTA
                AppButton(
                  label: 'Start Delivery Shift',
                  icon: Icons.two_wheeler_rounded,
                  busy: _busy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

