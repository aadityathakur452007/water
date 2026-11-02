import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../../../shared/ui/app_button.dart';

class PodSheet extends StatefulWidget {
  const PodSheet({
    super.key,
    required this.stop,
    required this.api,
    required this.onSuccess,
  });

  final Map<String, dynamic> stop;
  final ApiClient api;
  final VoidCallback onSuccess;

  @override
  State<PodSheet> createState() => _PodSheetState();
}

class _PodSheetState extends State<PodSheet> {
  final _otpController = TextEditingController();
  late int _emptiesCount;
  bool _cashReceived = false;
  bool _busy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Default empties to fulls expected for quick 1-tap confirmation
    _emptiesCount = widget.stop['empties_expected'] is int
        ? widget.stop['empties_expected'] as int
        : (widget.stop['quantity'] is int ? widget.stop['quantity'] as int : 1);
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _makeCall(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    if (cleaned.isEmpty) return;
    final uri = Uri.parse('tel:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _submit() async {
    final otp = _otpController.text.trim();
    if (otp.length < 4) {
      setState(() => _errorMessage = 'Enter the 6-digit delivery OTP from customer');
      return;
    }

    final isCod = widget.stop['payment_mode'] == 'cod';
    final amountDue = widget.stop['amount_due'] as int? ?? 0;
    if (isCod && amountDue > 0 && !_cashReceived) {
      setState(() => _errorMessage = 'Please confirm cash collection before completing delivery');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      await widget.api.completeDelivery(
        stopId: widget.stop['id'].toString(),
        deliveryOtp: otp,
        emptiesCount: _emptiesCount,
        cash: isCod ? amountDue : 0,
      );
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
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
    final stop = widget.stop;
    final customerName = stop['customer_name']?.toString() ?? 'Customer';
    final phone = stop['customer_phone']?.toString() ?? '';
    final qty = stop['quantity']?.toString() ?? '1';
    final address = (stop['address'] as Map<String, dynamic>?) ?? {};
    final formattedAddress = address['formatted']?.toString() ?? 'Delivery address';
    final landmark = address['landmark']?.toString() ?? '';
    final hasLift = address['has_lift'] == true;
    final isCod = stop['payment_mode'] == 'cod';
    final amountDue = stop['amount_due'] as int? ?? 0;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Bar: Modal Title + Bottles to Deliver Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'DOORSTEP HANDOVER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: ShodashaTheme.muted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: ShodashaTheme.tealTint,
                      borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                    ),
                    child: Text(
                      '$qty × 20L Cane',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: ShodashaTheme.tealDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Customer Name + Phone Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customerName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: ShodashaTheme.ink,
                          ),
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            phone,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ShodashaTheme.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (phone.isNotEmpty)
                    IconButton.filledTonal(
                      tooltip: 'Call customer',
                      onPressed: () => _makeCall(phone),
                      icon: const Icon(Icons.call_rounded, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: ShodashaTheme.tealTint,
                        foregroundColor: ShodashaTheme.teal,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Full Delivery Address Card with Landmark and Lift status
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: ShodashaTheme.bg,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                  border: Border.all(color: ShodashaTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 16,
                          color: ShodashaTheme.teal,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            formattedAddress,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ShodashaTheme.ink,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (landmark.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: Text(
                          'Landmark: $landmark',
                          style: const TextStyle(
                            fontSize: 11,
                            color: ShodashaTheme.muted,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Row(
                        children: [
                          Icon(
                            hasLift ? Icons.elevator_rounded : Icons.stairs_rounded,
                            size: 14,
                            color: hasLift ? ShodashaTheme.successDark : ShodashaTheme.warningDark,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasLift ? 'Lift Available' : 'No Lift (Stairs)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: hasLift ? ShodashaTheme.successDark : ShodashaTheme.warningDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // OTP Input Box
              const Text(
                'Customer Delivery OTP',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ShodashaTheme.ink,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                autofocus: true,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                  color: ShodashaTheme.ink,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '• • • • • •',
                  hintStyle: const TextStyle(
                    fontSize: 22,
                    color: ShodashaTheme.border,
                    letterSpacing: 8,
                  ),
                  filled: true,
                  fillColor: ShodashaTheme.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                    borderSide: const BorderSide(color: ShodashaTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                    borderSide: const BorderSide(color: ShodashaTheme.teal, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // Empty Cans Returned Counter
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: ShodashaTheme.bg,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                  border: Border.all(color: ShodashaTheme.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Empty Canes Collected',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ShodashaTheme.ink,
                          ),
                        ),
                        Text(
                          'Doorstep bottle return',
                          style: TextStyle(
                            fontSize: 11,
                            color: ShodashaTheme.muted,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _emptiesCount > 0
                              ? () => setState(() => _emptiesCount--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                          color: ShodashaTheme.ink,
                        ),
                        Text(
                          '$_emptiesCount',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: ShodashaTheme.ink,
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _emptiesCount++),
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          color: ShodashaTheme.teal,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Cash Collection Checkbox (if COD)
              if (isCod && amountDue > 0) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: ShodashaTheme.warningTint.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                    border: Border.all(color: ShodashaTheme.warning),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _cashReceived,
                        activeColor: ShodashaTheme.warningDark,
                        onChanged: (v) => setState(() => _cashReceived = v ?? false),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Collect ₹${(amountDue / 100).toStringAsFixed(0)} Cash',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: ShodashaTheme.ink,
                              ),
                            ),
                            const Text(
                              'Confirm cash received in hand',
                              style: TextStyle(
                                fontSize: 11,
                                color: ShodashaTheme.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: ShodashaTheme.dangerTint,
                    borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: ShodashaTheme.dangerDark,
                        size: 18,
                      ),
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

              // Action Buttons
              AppButton(
                label: 'Verify OTP & Mark Delivered',
                kind: AppButtonKind.primary,
                busy: _busy,
                onPressed: _busy ? null : _submit,
              ),
              const SizedBox(height: AppSpacing.xs),
              AppButton(
                label: 'Cancel',
                kind: AppButtonKind.secondary,
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
