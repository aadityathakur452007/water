// Donor login screen (76e0eba), customer portal only.
//
// The donor's local "any 4 digits" check, hardcoded partner registry and
// rider/plant navigation are deliberately gone. This screen talks to the
// real OTP API:
//   POST /auth/otp/start  -> channel + cooldown
//   POST /auth/otp/verify -> session
// Server-code channels (fast2sms/textbee) return a 6-digit SMS. The default
// Firebase channel needs a Firebase client SDK that this build does not have;
// that case is explained honestly and the server-gated demo door stays
// available for QA. No OTP is ever accepted locally.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import 'auth_controller.dart';
import 'demo_sheet.dart';

class DonorLoginScreen extends StatefulWidget {
  const DonorLoginScreen({super.key, required this.controller, this.notice});

  final AuthController controller;
  final String? notice;

  @override
  State<DonorLoginScreen> createState() => _DonorLoginScreenState();
}

class _DonorLoginScreenState extends State<DonorLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  bool _isOtpSent = false;
  bool _isBusy = false;
  bool _sending = false;
  int _timerSeconds = 30;
  Timer? _resendTimer;
  String? _notice;

  AuthController get _auth => widget.controller;

  @override
  void dispose() {
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startTimer(int seconds) {
    _timerSeconds = seconds <= 0 ? 30 : seconds;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_timerSeconds > 1) {
        setState(() => _timerSeconds--);
      } else {
        timer.cancel();
        setState(() => _timerSeconds = 0);
      }
    });
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error
              ? const Color(0xFFDC2626)
              : AppColors.primaryDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
  }

  Future<void> _requestOtp() async {
    final phone = _phoneController.text.trim();
    if (!isValidIndianPhone(phone)) {
      _showMessage('Enter a valid 10-digit Indian mobile number.', error: true);
      return;
    }
    setState(() {
      _isBusy = true;
      _sending = true;
      _notice = null;
    });
    final result = await _auth.startOtp(phone);
    if (!mounted) return;

    if (result == null) {
      setState(() {
        _isBusy = false;
        _sending = false;
      });
      _showMessage(
        _auth.errorMessage ?? 'Could not send the code.',
        error: true,
      );
      return;
    }

    if (!result.serverCode) {
      // Firebase path: the API accepted the request but expects a Firebase
      // client ID token. This build has no Firebase SDK/config, so do not
      // pretend an SMS was sent and do not accept a local code.
      setState(() {
        _isBusy = false;
        _sending = false;
        _notice =
            'This server is set to Firebase OTP. Configure the API with '
            'OTP_PROVIDER=fast2sms or textbee (or use demo access) to sign in.';
      });
      _showMessage(
        'Firebase OTP is not configured in this build.',
        error: true,
      );
      return;
    }

    setState(() {
      _isBusy = false;
      _sending = false;
      _isOtpSent = true;
    });
    _startTimer(result.resendAfterSeconds);
    _otpFocusNodes.first.requestFocus();
    _showMessage('Verification code sent to +91 $phone');
  }

  Future<void> _verifyOtp() async {
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length != 6) {
      _showMessage('Enter the 6-digit verification code.', error: true);
      return;
    }
    setState(() {
      _isBusy = true;
      _notice = null;
    });
    final ok = await _auth.verifyOtp(_phoneController.text, code);
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (!ok) {
      _showMessage(
        _auth.errorMessage ?? 'Could not verify the code.',
        error: true,
      );
      _otpFocusNodes.first.requestFocus();
    }
    // Success: AuthGate rebuilds on the controller and swaps to the shell.
  }

  void _editPhone() {
    setState(() {
      _isOtpSent = false;
      _notice = null;
      for (final c in _otpControllers) {
        c.clear();
      }
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _hero(),
              if (widget.notice != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF9C3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE047)),
                    ),
                    child: Text(
                      widget.notice!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF713F12),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _isOtpSent ? _otpSection() : _phoneSection(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 20, bottom: 24, left: 20, right: 20),
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
            height: 220,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox(
              height: 180,
              child: Icon(
                Icons.water_drop_rounded,
                size: 90,
                color: AppColors.money,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'SHODASHA MINERAL\nWATER SERVICE',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
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

  Widget _phoneSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mobile Number',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          enabled: !_isBusy,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
          decoration: InputDecoration(
            counterText: '',
            prefixIcon: Container(
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
            ),
            hintText: 'Enter 10-digit mobile number',
            hintStyle: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF94A3B8),
            ),
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
              borderSide: const BorderSide(color: AppColors.money, width: 2),
            ),
            filled: true,
            fillColor: AppColors.background,
          ),
        ),
        if (_notice != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF9C3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE047)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Color(0xFF854D0E),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _notice!,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: Color(0xFF713F12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isBusy ? null : _requestOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.money,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _sending
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Get Verification Code',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _isBusy ? null : _openDemo,
            child: const Text(
              'Demo access (QA)',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text(
            'By continuing, you agree to Shodasha Terms & Privacy Policy',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
          ),
        ),
      ],
    );
  }

  Widget _otpSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF86EFAC)),
          ),
          child: const Row(
            children: [
              Icon(Icons.verified_user, color: AppColors.money, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VERIFIED CUSTOMER ACCOUNT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'Customer Account',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.money,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Verification Code',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sent to +91 ${_phoneController.text}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: _isBusy ? null : _editPhone,
              child: const Text(
                'Edit Phone',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppColors.money,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: List.generate(6, (index) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == 5 ? 0 : 6),
                child: SizedBox(
                  height: 56,
                  child: TextField(
                    controller: _otpControllers[index],
                    focusNode: _otpFocusNodes[index],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    enabled: !_isBusy,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.money,
                          width: 2,
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty && index < 5) {
                        _otpFocusNodes[index + 1].requestFocus();
                      } else if (value.isEmpty && index > 0) {
                        _otpFocusNodes[index - 1].requestFocus();
                      }
                    },
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _timerSeconds > 0
                  ? 'Resend code in ${_timerSeconds}s'
                  : "Didn't receive the code? ",
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            if (_timerSeconds == 0)
              GestureDetector(
                onTap: _isBusy ? null : _requestOtp,
                child: const Text(
                  'Resend OTP',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.money,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isBusy ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.money,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isBusy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Confirm & Enter',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
        if (_auth.errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _auth.errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFFB91C1C)),
          ),
        ],
      ],
    );
  }
}
