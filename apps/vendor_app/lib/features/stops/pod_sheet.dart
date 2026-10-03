// PoD sheet: customer OTP + empties/cash confirm + seal check.
// GPS is captured best-effort; drift only soft-flags (never blocks).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import 'stops_controller.dart';

class PodSheet extends StatefulWidget {
  const PodSheet({
    super.key,
    required this.controller,
    required this.stopId,
    this.collectPaise = 0,
    this.paymentMode = 'cod',
  });

  final StopsController controller;
  final String stopId;

  /// 015: collect hint from the joined stop (total + mode).
  final int collectPaise;
  final String paymentMode;

  @override
  State<PodSheet> createState() => _PodSheetState();
}

class _PodSheetState extends State<PodSheet> {
  final _otp = TextEditingController();
  final _empties = TextEditingController(text: '0');
  final _cash = TextEditingController(text: '0');
  bool _sealOk = true;

  @override
  void dispose() {
    _otp.dispose();
    _empties.dispose();
    _cash.dispose();
    super.dispose();
  }

  Future<Position?> _position() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.medium));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ready = _otp.text.trim().length >= 4 && !c.submitting;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('PoD / डिलीवरी पूरी करें',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const Text('Customer ke phone par OTP batayein',
                style: TextStyle(color: ShodashaTheme.muted)),
            // 015: amount to collect (mode line only when total unknown).
            Text(
              widget.collectPaise > 0
                  ? '${widget.paymentMode.toUpperCase()} • Collect ${rupees(widget.collectPaise)}'
                  : widget.paymentMode.toUpperCase(),
              style: const TextStyle(
                  color: ShodashaTheme.blue, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _otp,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Delivery OTP',
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _empties,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Khaali ginati'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _cash,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration:
                        const InputDecoration(labelText: 'Cash (Rs)'),
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Seal sahi / सील ठीक है'),
              value: _sealOk,
              activeColor: ShodashaTheme.blue,
              onChanged: (v) => setState(() => _sealOk = v ?? true),
            ),
            ElevatedButton(
              onPressed: !ready
                  ? null
                  : () async {
                      final pos = await _position();
                      final ok = await c.completePod(
                        stopId: widget.stopId,
                        deliveryOtp: _otp.text.trim(),
                        emptiesCount:
                            int.tryParse(_empties.text.trim()) ?? 0,
                        cashPaise:
                            (int.tryParse(_cash.text.trim()) ?? 0) * 100,
                        sealOk: _sealOk,
                        lat: pos?.latitude,
                        lng: pos?.longitude,
                      );
                      if (context.mounted && ok) {
                        Navigator.of(context).pop();
                      }
                      if (context.mounted && !ok && c.notice != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(c.notice!)));
                      }
                    },
              child: Text(c.submitting
                  ? 'Complete ho raha…'
                  : 'Delivery complete karein'),
            ),
          ],
        ),
      ),
    );
  }
}
