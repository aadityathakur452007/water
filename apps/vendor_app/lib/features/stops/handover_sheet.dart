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
    this.outbox,
    this.collectPaise = 0,
    this.paymentMode = 'cod',
    this.tripleAlreadyDone = false,
  });

  final StopsController controller;
  final String stopId;
  final int fullsExp;
  final int emptiesExp;
  final SyncController? outbox;
  final int collectPaise;
  final String paymentMode;
  final bool tripleAlreadyDone;

  @override
  State<HandoverSheet> createState() => _HandoverSheetState();
}

class _HandoverSheetState extends State<HandoverSheet> {
  late int _step; // 0 = Bottles & Cash, 1 = Customer OTP

  // Step 1 state
  late int _fulls;
  late int _empties;
  int _caps = 0;
  int _damaged = 0;
  String _damageReason = 'cracked';
  late final TextEditingController _cash;
  late final TextEditingController _upi;

  // Step 2 state
  final TextEditingController _otp = TextEditingController();
  bool _sealOk = true;

  @override
  void initState() {
    super.initState();
    _step = widget.tripleAlreadyDone ? 1 : 0;
    _fulls = widget.fullsExp;
    _empties = widget.emptiesExp;

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

  Widget _stepper(String label, int value, ValueChanged<int> onChanged, {Color? color}) {
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
            icon: Icon(Icons.add_circle_outline, color: color ?? ShodashaTheme.blue),
            iconSize: 32,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }

  Future<void> _submitHandover() async {
    final c = widget.controller;
    final otpStr = _otp.text.trim();
    if (otpStr.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer ka 4-6 digit OTP darj karein')),
      );
      return;
    }

    final cashPaise = _rs(_cash) * 100;
    final upiPaise = _rs(_upi) * 100;

    // 1. Commit Triple if not already recorded
    if (!widget.tripleAlreadyDone) {
      late final Map<String, dynamic> tripleBody;
      try {
        tripleBody = buildTripleBody(
          fullsGiven: _fulls,
          emptiesBack: _empties,
          cashPaise: cashPaise,
          upiPaise: upiPaise,
          capsMissing: _caps,
          damagedEmpties: _damaged,
          emptyCondition: _damaged > 0 ? _damageReason : null,
          version: c.version,
        );
      } on ArgumentError catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
        return;
      }

      final tripleOk = await c.commitTriple(
        stopId: widget.stopId,
        triple: tripleBody,
      );

      if (!tripleOk) {
        if ((c.notice ?? '').contains('Sync me queue') && widget.outbox != null) {
          await widget.outbox!.enqueue(
            stopId: widget.stopId,
            triple: tripleBody,
          );
        } else {
          if (mounted && c.notice != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(c.notice!)));
          }
          return;
        }
      }
    }

    // 2. Complete PoD with OTP and location
    final pos = await _position();
    final podBody = buildPodBody(
      deliveryOtp: otpStr,
      emptiesCount: _empties,
      cashPaise: cashPaise,
      sealOk: _sealOk,
      lat: pos?.latitude,
      lng: pos?.longitude,
    );

    final podOk = await c.completePod(
      stopId: widget.stopId,
      deliveryOtp: otpStr,
      emptiesCount: _empties,
      cashPaise: cashPaise,
      sealOk: _sealOk,
      lat: pos?.latitude,
      lng: pos?.longitude,
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
        Navigator.of(context).pop();
      } else if (c.notice != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(c.notice!)));
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
                'Expected: ${widget.fullsExp} jars • ${widget.emptiesExp} wapas',
                style: const TextStyle(fontSize: 13, color: ShodashaTheme.muted),
              ),
              if (widget.collectPaise > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${widget.paymentMode.toUpperCase()} • Collect ${rupees(widget.collectPaise)}',
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
                _stepper('Jars diye (Full)', _fulls, (v) => setState(() => _fulls = v)),
                _stepper('Khaali wapas (Empty)', _empties, (v) => setState(() {
                      _empties = v;
                      if (_damaged > v) _damaged = v;
                    })),
                if (_empties > 0) ...[
                  _stepper(
                    vtr('टूटा या खराब जार ($_damaged)', 'Damaged jar ($_damaged)'),
                    _damaged,
                    (v) => setState(() => _damaged = v),
                    color: Colors.deepOrange,
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
                ],
                _stepper('Bina dhakkan ($_caps × Rs 3 = Rs $capRs)', _caps,
                    (v) => setState(() => _caps = v)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cash,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Cash liya (Rs)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _upi,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'UPI liya (Rs)',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                AppButton(
                  label: 'Aage: Customer OTP',
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
                          const Text('Jars', style: TextStyle(fontSize: 11, color: ShodashaTheme.muted)),
                          Text('$_fulls', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        ],
                      ),
                      Column(
                        children: [
                          const Text('Empties', style: TextStyle(fontSize: 11, color: ShodashaTheme.muted)),
                          Text('$_empties', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        ],
                      ),
                      Column(
                        children: [
                          const Text('Collected', style: TextStyle(fontSize: 11, color: ShodashaTheme.muted)),
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
                  maxLength: 6,
                  autofocus: true,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Customer Delivery OTP',
                    hintText: '4 ya 6 digit OTP',
                    counterText: '',
                    prefixIcon: Icon(Icons.pin_outlined),
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (!widget.tripleAlreadyDone)
                      Expanded(
                        flex: 1,
                        child: AppButton(
                          label: 'Peechhe',
                          kind: AppButtonKind.secondary,
                          onPressed: c.submitting ? null : () => setState(() => _step = 0),
                        ),
                      ),
                    if (!widget.tripleAlreadyDone) const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        label: c.submitting ? 'Complete ho raha…' : 'Delivery Complete',
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
