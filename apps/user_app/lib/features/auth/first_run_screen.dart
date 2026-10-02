// 006-auth-flow — First-run sheet: location + notification permission,
// then the address-first empty state ("Add your address").
//
// Shown once per install when the user owns zero addresses (guest or
// authed). Denied permissions never dead-end: the map-pin path works
// manually. Completion/skip persists in SharedPreferences.
// ui-checklist: Contacting Support (why + what next), form-submit states.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';

/// Prefs flag (v1 — bump when the flow changes shape).
const String kFirstRunFlag = 'firstrun_done_v1';

/// True when the sheet should be offered (flag unset).
Future<bool> shouldOfferFirstRun() async {
  final prefs = await SharedPreferences.getInstance();
  return !(prefs.getBool(kFirstRunFlag) ?? false);
}

/// Persists completion OR skip (both stop future offers).
Future<void> markFirstRunDone() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kFirstRunFlag, true);
}

/// Offers the sheet exactly when it is useful: no addresses saved yet.
Future<void> maybeOfferFirstRun(
  BuildContext context, {
    required int addressCount,
    required VoidCallback onAddAddress,
  }) async {
  if (addressCount > 0 || !context.mounted) return;
  if (!await shouldOfferFirstRun()) return;
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (_) => _FirstRunSheet(onAddAddress: onAddAddress),
  );
  await markFirstRunDone();
}

enum _Step { locate, notify, address }

class _FirstRunSheet extends StatefulWidget {
  const _FirstRunSheet({required this.onAddAddress});

  final VoidCallback onAddAddress;

  @override
  State<_FirstRunSheet> createState() => _FirstRunSheetState();
}

class _FirstRunSheetState extends State<_FirstRunSheet> {
  _Step _step = _Step.locate;
  bool _busy = false;
  String? _note;

  Future<void> _askLocation() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    bool granted = await Geolocator.isLocationServiceEnabled();
    if (granted) {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      granted = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _Step.notify;
      if (!granted) {
        _note = 'Location off hai — address map par haath se pin lagayein';
      }
    });
  }

  Future<void> _askNotify() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    AuthorizationStatus status;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      status = settings.authorizationStatus;
    } catch (_) {
      status = AuthorizationStatus.notDetermined;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _Step.address;
      if (status != AuthorizationStatus.authorized &&
          status != AuthorizationStatus.provisional) {
        _note = 'Notification band hai — order updates app mein dikhenge';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_step == _Step.locate) ...[
              const Icon(Icons.location_on,
                  size: 32, color: ShodashaTheme.blue),
              const SizedBox(height: 8),
              const Text(
                'Delivery ke liye location',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 6),
              const Text(
                'Aas-paas ka address jaldi milega. Permission na dein to map par haath se pin laga sakte hain.',
                style: TextStyle(color: ShodashaTheme.muted, fontSize: 14),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _askLocation,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Location chalu karein'),
                ),
              ),
            ] else if (_step == _Step.notify) ...[
              const Icon(Icons.notifications_outlined,
                  size: 32, color: ShodashaTheme.blue),
              const SizedBox(height: 8),
              const Text(
                'Order updates paayein',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 6),
              const Text(
                'Dispatch, arrival window aur delivery receipt ki khabar milegi.',
                style: TextStyle(color: ShodashaTheme.muted, fontSize: 14),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _askNotify,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Notification chalu karein'),
                ),
              ),
            ] else ...[
              const Icon(Icons.home_outlined,
                  size: 32, color: ShodashaTheme.blue),
              const SizedBox(height: 8),
              const Text(
                'Apna address jodein',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 6),
              const Text(
                'Pehla address map par pin lagakar save karein — delivery isi par hogi.',
                style: TextStyle(color: ShodashaTheme.muted, fontSize: 14),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onAddAddress();
                  },
                  child: const Text('Address jodein'),
                ),
              ),
            ],
            if (_note != null) ...[
              const SizedBox(height: 8),
              Text(_note!,
                  style: const TextStyle(
                      fontSize: 13, color: ShodashaTheme.blue)),
            ],
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Baad mein',
                  style: TextStyle(color: ShodashaTheme.muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
