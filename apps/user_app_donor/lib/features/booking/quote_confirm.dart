// Order confirmation (server truth, clear next steps).
//
// Shows the SERVER-minted order id (never a client-key preview), window,
// amount, rider note. Primary = Track order; subscription checkouts get a
// subscriptions shortcut. Money values come from [CheckoutResult] only.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'booking_controller.dart';
import 'checkout_service.dart';

/// Shows the confirmation sheet for a placed [CheckoutResult].
void showOrderConfirm(
  BuildContext context, {
  required CheckoutResult result,
  VoidCallback? onTrackOrder,
  VoidCallback? onOpenSubscriptions,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: ShodashaTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ShodashaTheme.radiusSheet),
      ),
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
    this.onTrackOrder,
    this.onOpenSubscriptions,
  });

  final CheckoutResult result;
  final VoidCallback? onTrackOrder;
  final VoidCallback? onOpenSubscriptions;

  void _primary(BuildContext context) {
    Navigator.of(context).pop();
    if (result.isSubscription) {
      onOpenSubscriptions?.call();
    } else {
      onTrackOrder?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = result;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  r.attention ? Icons.info_outline : Icons.check_circle_outline,
                  color: r.attention ? ShodashaTheme.blue : ShodashaTheme.teal,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.attention
                        ? (r.isSubscription
                              ? 'Plan created'
                              : 'Order placed — payment pending')
                        : 'Order confirmed',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (r.attention) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ShodashaTheme.blueTint,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                ),
                child: Text(
                  r.attentionMessage,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: ShodashaTheme.border),
                borderRadius: BorderRadius.circular(ShodashaTheme.radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.isSubscription
                      ? r.subscriptionId.isNotEmpty
                      : r.orderId.isNotEmpty)
                    Text(
                      r.isSubscription
                          ? 'Subscription: ${r.subscriptionId}'
                          : 'Order: ${r.orderId}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  const SizedBox(height: 2),
                  Text('Window: ${r.windowLabel}'),
                  if (r.waterPaise > 0 || r.depositPaise > 0)
                    Text(
                      'Water ${rupeesLabel(r.waterPaise)}'
                      '${r.depositPaise > 0 ? ' + Deposit ${rupeesLabel(r.depositPaise)}' : ''}'
                      '${r.capsPaise > 0 ? ' + Cap ${rupeesLabel(r.capsPaise)} (at handover)' : ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  if (r.totalPaise > 0)
                    Text(
                      'Amount: ${rupeesLabel(r.totalPaise)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  if (r.addressLabel.isNotEmpty)
                    Text(
                      'Address: ${r.addressLabel}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  if (!r.attention)
                    const Text(
                      'The rider name and call button appear once assigned.',
                      style: TextStyle(
                        color: ShodashaTheme.muted,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            if (r.upiPending && !r.attention) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ShodashaTheme.blueTint,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                ),
                child: const Text(
                  'UPI payment sent — it can take up to 10 minutes to show '
                  'as paid in Orders. If it does not, contact support.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
            if (r.isSubscription) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onOpenSubscriptions?.call();
                },
                child: const Text('Pause or skip any time'),
              ),
            ],
            if (!r.attention) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ShodashaTheme.tealTint,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: ShodashaTheme.teal,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your safety deposit is tracked in the app — see '
                        'the Wallet tab.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ShodashaTheme.teal,
                  foregroundColor: ShodashaTheme.surface,
                ),
                onPressed: () => _primary(context),
                child: Text(
                  r.isSubscription ? 'View subscriptions' : 'Track order',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Done',
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
