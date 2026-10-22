// P2-2 — one-time first-run address prompt.
//
// Shown once per install to an authenticated user whose address list loaded
// empty. Completion and "Not now" both persist, so the sheet never nags.
// The primary action opens Addresses, which owns the form + map picker (the
// sheet itself collects no fields). English copy per ADR-120.

import 'package:flutter/material.dart';
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

/// Offers the sheet; returns after it closes. Never throws when prefs fail —
/// the sheet is an onboarding nicety, not a gate.
Future<void> maybeOfferFirstRun(
  BuildContext context, {
  required VoidCallback onAddAddress,
}) async {
  bool offer;
  try {
    offer = await shouldOfferFirstRun();
  } catch (_) {
    return;
  }
  if (!offer || !context.mounted) return;

  final add = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ShodashaTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ShodashaTheme.radiusSheet),
      ),
    ),
    builder: (_) => const _FirstRunSheet(),
  );
  try {
    await markFirstRunDone();
  } catch (_) {
    // A failed prefs write only means the sheet may appear once more.
  }
  if (add == true && context.mounted) onAddAddress();
}

class _FirstRunSheet extends StatelessWidget {
  const _FirstRunSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: ShodashaTheme.tealTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on,
                color: ShodashaTheme.teal,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Set your delivery address',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                color: ShodashaTheme.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add your address once and ordering takes a tap. You can '
              'change it anytime in Addresses.',
              style: TextStyle(color: ShodashaTheme.muted, fontSize: 14),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: ShodashaTheme.minTarget,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ShodashaTheme.teal,
                  foregroundColor: ShodashaTheme.surface,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Add address'),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: ShodashaTheme.muted,
                minimumSize: const Size.fromHeight(ShodashaTheme.minTarget),
              ),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
