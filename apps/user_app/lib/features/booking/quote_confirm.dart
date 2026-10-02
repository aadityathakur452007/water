// 005-home-ux — Order confirmation (server truth, clear next steps).
//
// ui-checklist Making-a-Payment: success indicator + what happens next.
// Shows the SERVER-minted order id (never a client-key preview), window,
// amount, rider note. Primary = Track order; subscription checkouts get a
// pause/skip shortcut. WhatsApp lives on the bill screen only —
// never as the post-purchase primary (user-reported confusion).

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'checkout_service.dart';

/// Shows the confirmation sheet for a placed [CheckoutResult].
void showOrderConfirm(
  BuildContext context, {
    required CheckoutResult result,
    required VoidCallback onTrackOrder,
    required VoidCallback onOpenSubscriptions,
  }) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (_) => _ConfirmSheet(
      result: result,
      onTrackOrder: onTrackOrder,
      onOpenSubscriptions: onOpenSubscriptions,
    ),
  );
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.result,
    required this.onTrackOrder,
    required this.onOpenSubscriptions,
  });

  final CheckoutResult result;
  final VoidCallback onTrackOrder;
  final VoidCallback onOpenSubscriptions;

  @override
  Widget build(BuildContext context) {
    final r = result;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: ShodashaTheme.success,
                  size: 28,
                ),
                SizedBox(width: 8),
                Text(
                  'Order confirm ho gaya',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: ShodashaTheme.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!r.isSubscription)
                    Text('ID: ${r.orderId}')
                  else
                    Text('Subscription: ${r.subscriptionId}'),
                  Text('Window: ${r.windowLabel}'),
                  Text(
                    'Rakam: Rs ${r.totalPaise ~/ 100}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Text(
                    'Rider assign hote hi naam + call button ayega',
                    style: TextStyle(
                      color: ShodashaTheme.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (r.isSubscription) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onOpenSubscriptions();
                },
                child: const Text('Pause / skip kabhi bhi kar sakte hain'),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onTrackOrder();
                },
                child: Text(
                  r.isSubscription ? 'Subscriptions dekhein' : 'Track order',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Ho gaya',
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
