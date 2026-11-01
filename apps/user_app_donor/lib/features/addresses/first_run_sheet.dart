// P2-2 — one-time first-run address prompt.
//
// Shown once per install to an authenticated user whose address list loaded
// empty. Completion and "Not now" both persist, so the sheet never nags.
// The primary action opens Addresses, which owns the form + map picker (the
// sheet itself collects no fields). English copy per ADR-120.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';

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
  if (add != null) {
    try {
      await markFirstRunDone();
    } catch (_) {
      // A failed prefs write only means the sheet may appear once more.
    }
  }
  if (add == true && context.mounted) onAddAddress();
}

class _FirstRunSheet extends StatelessWidget {
  const _FirstRunSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.md,
        ),
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
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Where should we deliver?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: ShodashaTheme.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Save your address once for 1-tap reordering. You can '
              'edit it anytime.',
              style: TextStyle(
                color: ShodashaTheme.muted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Add address',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppSpacing.sm),
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
