// S5 — Rating bottom sheet (once per delivered order + complaint shortcut).
// Contract §4.4 + user-flows flow 6 (≤3 stars offers complaint with order
// pre-attached; 3-day window; photos = v2).
//
// Auto-popup on first delivered view + manual button (ported F4 behavior).
// The complaint shortcut is the nullable S8 door: rendered only when the
// shell wires `onSupport`, so this slice never promises a screen it lacks.
//
// States.md covered: idle, star picked, submitting (spinner), success,
// failure (rate-once copy), already rated.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'orders_controller.dart';

/// Shows the rating sheet for [order] (auto or manual entry point).
Future<void> showRatingSheet(
  BuildContext context,
  OrdersController controller,
  Order order, {
  VoidCallback? onSupport,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: ShodashaTheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ShodashaTheme.radiusSheet),
      ),
    ),
    builder: (_) =>
        RatingSheet(controller: controller, order: order, onSupport: onSupport),
  );
}

/// 1–5 star sheet; submit disabled until a star is picked or already rated.
class RatingSheet extends StatefulWidget {
  const RatingSheet({
    super.key,
    required this.controller,
    required this.order,
    this.onSupport,
  });

  final OrdersController controller;
  final Order order;
  final VoidCallback? onSupport;

  @override
  State<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<RatingSheet> {
  int _stars = 0;
  bool _busy = false;

  Future<void> _submit() async {
    if (_stars < 1 || _busy) return;
    setState(() => _busy = true);
    final result = await widget.controller.rate(widget.order.id, _stars);
    if (!mounted) return;
    if (result == RateResult.failed) {
      // Network/401: keep the sheet open so the user can retry instead of
      // being told a rating was already received.
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ordersStringsHi['rateFailed']!)));
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == RateResult.success
              ? ordersStringsHi['rateThanks']!
              : ordersStringsHi['rateAgain']!,
        ),
      ),
    );
  }

  void _complaint() {
    // WHY: the S8 support screen owns complaints; this sheet only forwards
    // the intent after closing itself (backend already holds the order).
    final onSupport = widget.onSupport;
    if (onSupport == null) return;
    Navigator.of(context).pop();
    onSupport();
  }

  @override
  Widget build(BuildContext context) {
    final alreadyRated = widget.order.rated;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ordersStringsHi['rateTitle']!,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ShodashaTheme.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    iconSize: 36,
                    tooltip: '$i / 5',
                    onPressed: alreadyRated
                        ? null
                        : () => setState(() => _stars = i),
                    icon: Icon(
                      i <= _stars ? Icons.star : Icons.star_border,
                      color: i <= _stars
                          ? ShodashaTheme.solarDark
                          : ShodashaTheme.muted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: ShodashaTheme.minTarget,
              child: ElevatedButton(
                onPressed: (alreadyRated || _stars < 1 || _busy)
                    ? null
                    : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ShodashaTheme.ink,
                  foregroundColor: ShodashaTheme.surface,
                  disabledBackgroundColor: ShodashaTheme.ink.withValues(
                    alpha: 0.3,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ShodashaTheme.surface,
                        ),
                      )
                    : Text(ordersStringsHi['rateSubmit']!),
              ),
            ),
            if (widget.onSupport != null) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _complaint,
                  style: TextButton.styleFrom(
                    foregroundColor: ShodashaTheme.blue, // link only
                    minimumSize: const Size(48, ShodashaTheme.minTarget),
                  ),
                  child: Text(ordersStringsHi['complaintShortcut']!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
