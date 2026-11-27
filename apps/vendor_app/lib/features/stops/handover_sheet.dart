// Handover sheet: Unified 2-step doorstep completion modal.
// Step 1: Bottles & Payment (fulls, empties, damaged, caps, cash/upi).
// Step 2: Customer Verification (OTP, seal check, GPS capture, final completion).
// Eliminates fragmented dual-sheet confusion and keeps jar & cash counts synchronized.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/vendor_locale.dart';
import '../sync/sync_controller.dart';
import 'stops_controller.dart';
import '../../shared/ui/app_button.dart';

class HandoverSheet extends StatefulWidget {
  const HandoverSheet({
    super.key,
    required this.controller,
    required this.stopId,
    required this.fullsExp,
    required this.emptiesExp,
    this.jarsHeld,
    this.outbox,
    this.collectPaise = 0,
    this.paymentMode = 'cod',
    this.tripleAlreadyDone = false,
    this.onCompleted,
  });

  final StopsController controller;
  final String stopId;
  final int fullsExp;
  final int emptiesExp;
  final int? jarsHeld;
  final SyncController? outbox;
  final int collectPaise;
  final String paymentMode;
  final bool tripleAlreadyDone;
  final VoidCallback? onCompleted;

  @override
  State<HandoverSheet> createState() => _HandoverSheetState();
}

class _HandoverSheetState extends State<HandoverSheet> {
  late int _step; // 0 = Bottles & Cash, 1 = Customer OTP

  // Step 1 state
  late int _fulls;
  late int _empties;
  late final int _maxEmpties;
  int _caps = 0;
  int _damaged = 0;
  String _damageReason = 'cracked';
  late final TextEditingController _cash;
  late final TextEditingController _upi;

  // Step 2 state
  final TextEditingController _otp = TextEditingController();
  bool _sealOk = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _step = widget.tripleAlreadyDone ? 1 : 0;
    _fulls = widget.fullsExp;
    final held = widget.jarsHeld;
    if (held != null) {
      final cap = held < widget.fullsExp ? held : widget.fullsExp;
      _maxEmpties = cap < 0 ? 0 : cap;
    } else {
      _maxEmpties = widget.emptiesExp < 0 ? 0 : widget.emptiesExp;
    }
    _empties = widget.emptiesExp.clamp(0, _maxEmpties);

    final initialCash = (widget.collectPaise > 0 && widget.paymentMode.toLowerCase() == 'cod')
        ? (widget.collectPaise ~/ 100).toString()
        : '0';
    _cash = TextEditingController(text: initialCash);
    _upi = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _cash.dispose();
    _upi.dispose();
    _otp.dispose();
    super.dispose();
  }

  int _rs(TextEditingController t) => int.tryParse(t.text.trim()) ?? 0;

  Future<Position?> _position() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _stepper(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    int? maxValue,
    Color? color,
  }) {
    final atMax = maxValue != null && value >= maxValue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: color ?? ShodashaTheme.ink,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            iconSize: 32,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.add_circle_outline,
              color: atMax ? ShodashaTheme.muted : (color ?? ShodashaTheme.blue),
            ),
            iconSize: 32,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: atMax ? null : () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }

  Future<void> _submitHandover() async {
    final c = widget.controller;
    final otpStr = _otp.text.trim();
    if (otpStr.length < 4) {
      setState(() => _errorMessage = 'Enter the 4-digit delivery OTP from customer');
      return;
    }
    setState(() => _errorMessage = null);

    final cashPaise = _rs(_cash) * 100;

    // Single atomic PoD + bottle handover request: OTP is verified BEFORE
    // marking stop done or mutating ledger.held (zero half-done states).
    final pos = await _position();
    final podBody = buildPodBody(
      deliveryOtp: otpStr,
      emptiesCount: _empties,
      cashPaise: cashPaise,
      sealOk: _sealOk,
      lat: pos?.latitude,
      lng: pos?.longitude,
      fullsGiven: widget.tripleAlreadyDone ? null : _fulls,
      damagedEmpties: widget.tripleAlreadyDone ? null : _damaged,
      capsMissing: widget.tripleAlreadyDone ? null : _caps,
      emptyCondition: (!widget.tripleAlreadyDone && _damaged > 0)
          ? _damageReason
          : null,
    );

    final podOk = await c.completePod(
      stopId: widget.stopId,
      deliveryOtp: otpStr,
      emptiesCount: _empties,
      cashPaise: cashPaise,
      sealOk: _sealOk,
      lat: pos?.latitude,
      lng: pos?.longitude,
      fullsGiven: widget.tripleAlreadyDone ? null : _fulls,
      damagedEmpties: widget.tripleAlreadyDone ? null : _damaged,
      capsMissing: widget.tripleAlreadyDone ? null : _caps,
      emptyCondition: (!widget.tripleAlreadyDone && _damaged > 0)
          ? _damageReason
          : null,
    );

    if (!podOk && (c.notice ?? '').contains('Sync me queue') && widget.outbox != null) {
      await widget.outbox!.enqueuePod(
        stopId: widget.stopId,
        pod: podBody,
        cashAmountPaise: cashPaise,
      );
    }

    if (mounted) {
      if (podOk || (c.notice ?? '').contains('Sync me queue')) {
        widget.onCompleted?.call();
        Navigator.of(context).pop();
      } else {
        setState(() => _errorMessage = c.notice ?? 'Delivery completion failed. Please verify OTP.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final capRs = capChargeRs(_caps);
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: insets + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header & Step indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _step == 0 ? 'Doorstep Handover (1/2)' : 'Customer OTP (2/2)',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ShodashaTheme.blueTint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _step == 0 ? 'Step 1: Bottles' : 'Step 2: Verify',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ShodashaTheme.blue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                vtr(
                  'उम्मीद: ${widget.fullsExp} भरे जार • ${widget.emptiesExp} खाली',
                  'Expected: ${widget.fullsExp} full jars • ${widget.emptiesExp} empty returns',
                ),
                style: const TextStyle(fontSize: 13, color: ShodashaTheme.muted),
              ),
              if (widget.collectPaise > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${widget.paymentMode.toUpperCase()} • ${vtr('रुपये लें', 'Collect')} ${rupees(widget.collectPaise)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ShodashaTheme.blue,
                    ),
                  ),
                ),
              const Divider(height: 20),

              // Step 0: Bottles, Empties, Caps, Cash/UPI
              if (_step == 0) ...[
                _stepper(
                  vtr('जार दिए (भरे)', 'Delivered Jars (Full)'),
                  _fulls,
                  (v) => setState(() => _fulls = v.clamp(0, widget.fullsExp)),
                  maxValue: widget.fullsExp,
                ),
                if (_maxEmpties > 0) ...[
                  _stepper(
                    vtr('खाली वापस लिए', 'Empty Jars Returned'),
                    _empties,
                    (v) => setState(() {
                      _empties = v.clamp(0, _maxEmpties);
                      if (_damaged > _empties) _damaged = _empties;
                      if (_caps > _empties) _caps = _empties;
                    }),
                    maxValue: _maxEmpties,
                  ),
                  if (_empties > 0) ...[
                    _stepper(
                      vtr('टूटा या खराब जार ($_damaged)', 'Damaged jar ($_damaged)'),
                      _damaged,
                      (v) => setState(() => _damaged = v.clamp(0, _empties)),
                      maxValue: _empties,
                      color: ShodashaTheme.warning,
                    ),
                    if (_damaged > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DropdownButtonFormField<String>(
                          initialValue: _damageReason,
                          decoration: InputDecoration(
                            labelText: vtr('खराबी की वजह', 'Damage Reason'),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem(value: 'cracked', child: Text(vtr('फूटा हुआ', 'Cracked'))),
                            DropdownMenuItem(value: 'leaking', child: Text(vtr('छेद/लीक', 'Leaking'))),
                            DropdownMenuItem(value: 'dirty_oil', child: Text(vtr('गंदा या तेल लगा', 'Contaminated / Dirty'))),
                            DropdownMenuItem(value: 'broken_neck', child: Text(vtr('गर्दन टूटी हुई', 'Broken neck'))),
                          ],
                          onChanged: (v) => setState(() => _damageReason = v ?? 'cracked'),
                        ),
                      ),
                    _stepper(
                      vtr('बिना ढक्कन ($_caps × ₹3 = ₹$capRs)', 'Missing cap ($_caps × ₹3 = ₹$capRs)'),
                      _caps,
                      (v) => setState(() => _caps = v.clamp(0, _empties)),
                      maxValue: _empties,
                    ),
                  ],
                ] else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      vtr('पहला ऑर्डर — कोई खाली जार वापस नहीं लेना है', 'First-time order — 0 empty jars to collect'),
                      style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _cash,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(
                    labelText: vtr('कैश लिया (₹)', 'Cash Collected (₹)'),
                    counterText: '',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 18),
                AppButton(
                  label: vtr('आगे: कस्टमर OTP', 'Next: Customer OTP'),
                  icon: Icons.arrow_forward,
                  onPressed: () => setState(() => _step = 1),
                ),
              ],

              // Step 1: Customer OTP & Proof
              if (_step == 1) ...[
                // Recap card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ShodashaTheme.bg,
                    border: Border.all(color: ShodashaTheme.border),
                    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(vtr('जार', 'Jars'), style: const TextStyle(fontSize: 11, color: ShodashaTheme.muted)),
                          Text('$_fulls', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        ],
                      ),
                      Column(
                        children: [
                          Text(vtr('खाली', 'Empties'), style: const TextStyle(fontSize: 11, color: ShodashaTheme.muted)),
                          Text('$_empties', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        ],
                      ),
                      Column(
                        children: [
                          Text(vtr('रकम', 'Collected'), style: const TextStyle(fontSize: 11, color: ShodashaTheme.muted)),
                          Text(rupees((_rs(_cash) + _rs(_upi)) * 100),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: ShodashaTheme.blue)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _otp,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  autofocus: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    labelText: vtr('कस्टमर डिलीवरी OTP', 'Customer Delivery OTP'),
                    hintText: vtr('4 अंकों का OTP दर्ज करें', 'Enter 4-digit customer OTP'),
                    counterText: '',
                    prefixIcon: const Icon(Icons.pin_outlined),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(vtr('सील ठीक है', 'Seal intact')),
                  value: _sealOk,
                  activeColor: ShodashaTheme.blue,
                  onChanged: (v) => setState(() => _sealOk = v ?? true),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ShodashaTheme.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                      border: Border.all(color: ShodashaTheme.danger.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: ShodashaTheme.danger,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: ShodashaTheme.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (!widget.tripleAlreadyDone)
                      Expanded(
                        flex: 1,
                        child: AppButton(
                          label: vtr('पीछे', 'Back'),
                          kind: AppButtonKind.secondary,
                          onPressed: c.submitting ? null : () => setState(() => _step = 0),
                        ),
                      ),
                    if (!widget.tripleAlreadyDone) const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        label: c.submitting
                            ? vtr('पूरा हो रहा है…', 'Completing…')
                            : vtr('डिलीवरी पूरी करें', 'Complete Delivery'),
                        busy: c.submitting,
                        onPressed: (_otp.text.trim().length >= 4 && !c.submitting)
                            ? _submitHandover
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
