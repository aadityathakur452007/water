// F3 — Post-confirm screen: order ID + window + amount + WhatsApp share.
// ui-checklist Payment flow: confirmation + next steps + support link.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'booking_controller.dart';
import 'stepper.dart';

/// Shows the confirmation sheet (fire-and-forget from the booking sheet).
void unawaitedShowConfirm(
  BuildContext context, {
  required int totalPaise,
  required String idempotencyKey,
}) {
  // Order id is server-minted; show the client key prefix until F1 wires
  // POST /orders (then replace with the real order id, keep key for retry).
  final previewId = 'ORD-${idempotencyKey.substring(3, 9).toUpperCase()}';
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(kShodashaRadius),
      ),
    ),
    builder: (_) => QuoteConfirmSheet(
      orderId: previewId,
      totalPaise: totalPaise,
    ),
  );
}

class QuoteConfirmSheet extends StatelessWidget {
  const QuoteConfirmSheet({
    super.key,
    required this.orderId,
    required this.totalPaise,
  });

  final String orderId;
  final int totalPaise;

  @override
  Widget build(BuildContext context) {
    final day = nextServiceableDay(DateTime.now());
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Order confirm ho gaya',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: ShodashaColors.border),
                borderRadius: BorderRadius.circular(kShodashaRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ID: $orderId'),
                  Text('Window: ${day.day}/${day.month} subah (8–8)'),
                  Text(
                    'Rakam: ${rupeesLabel(totalPaise)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Text(
                    'Rider assign hote hi naam + call button ayega',
                    style: TextStyle(color: ShodashaColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PressScale(
                    // TODO(F1): share via share_plus / wa.me when deps land;
                    // today: copy bill text + SnackBar (guarded fallback).
                    onTap: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: 'Shodasha $orderId • '
                              '${rupeesLabel(totalPaise)} • '
                              '${day.day}/${day.month} subah',
                        ),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'WhatsApp app nahi mila — bill copy kiya gaya',
                            ),
                          ),
                        );
                      }
                    },
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ShodashaColors.ink, // black primary (locked)
                        borderRadius:
                            BorderRadius.circular(kShodashaRadius),
                      ),
                      child: const Text(
                        'WhatsApp par bhejein',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PressScale(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: ShodashaColors.border),
                      borderRadius: BorderRadius.circular(kShodashaRadius),
                    ),
                    child: const Text(
                      'Ho gaya',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
