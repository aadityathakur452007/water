// F4 — Rating bottom sheet (once per delivered order + complaint shortcut).
// Contract §4.4 + user-flows flow 6 (≤3 stars offers complaint with order
// pre-attached; 3-day window; photos = v2).
//
// Approved answer 5: auto-popup on first delivered view + manual button;
// complaint shortcut is a TODO route stub (SnackBar) — F-complaints owns it.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'orders_controller.dart';

/// Shows the rating sheet for [order] (auto or manual entry point).
Future<void> showRatingSheet(
  BuildContext context,
  OrdersController controller,
  Order order,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: OrdersTokens.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(OrdersTokens.radius),
      ),
    ),
    builder: (_) => RatingSheet(controller: controller, order: order),
  );
}

/// 1–5 star sheet; submit disabled until a star is picked or already rated.
class RatingSheet extends StatefulWidget {
  const RatingSheet({
    super.key,
    required this.controller,
    required this.order,
  });

  final OrdersController controller;
  final Order order;

  @override
  State<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<RatingSheet> {
  int _stars = 0;
  bool _busy = false;

  Future<void> _submit() async {
    if (_stars < 1 || _busy) return;
    setState(() => _busy = true);
    final ok = await widget.controller.rate(widget.order.id, _stars);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? ordersStringsHi['rateThanks']! : ordersStringsHi['rateAgain']!,
        ),
      ),
    );
  }

  void _complaint() {
    // TODO(F-complaints): push complaint route with order pre-attached
    // (reason code + ≤500 chars, ≤3-day window, photos v2).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ordersStringsHi['complaintStub']!)),
    );
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
                color: OrdersTokens.ink,
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
                      i <= _stars
                          ? Icons.star
                          : Icons.star_border,
                      color: OrdersTokens.blue,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: OrdersTokens.minTarget,
              child: ElevatedButton(
                onPressed:
                    (alreadyRated || _stars < 1 || _busy) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ShodashaTheme.ink,
                  foregroundColor: OrdersTokens.white,
                  disabledBackgroundColor:
                      OrdersTokens.blue.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(OrdersTokens.radius),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: OrdersTokens.white,
                        ),
                      )
                    : Text(ordersStringsHi['rateSubmit']!),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _complaint,
                style: TextButton.styleFrom(
                  foregroundColor: OrdersTokens.blue,
                  minimumSize:
                      const Size(48, OrdersTokens.minTarget),
                ),
                child: Text(ordersStringsHi['complaintShortcut']!),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
