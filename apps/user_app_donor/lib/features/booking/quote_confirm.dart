// Order confirmation (server truth, clean mobile receipt).
//
// Shows delivery window, amount, address, and payment instruction.
// Technical raw 36-char UUIDs are hidden from the primary receipt,
// rendered only as a quiet 8-char reference at the bottom.
// Primary action uses canonical AppButton.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import 'booking_controller.dart';
import 'checkout_service.dart';

String _shortRef(String id) {
  final clean = id.replaceAll('ord-', '').replaceAll('sub-', '');
  if (clean.length <= 8) return clean.toUpperCase();
  return clean.substring(0, 8).toUpperCase();
}

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
    final id = r.isSubscription ? r.subscriptionId : r.orderId;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
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
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    r.isSubscription
                        ? 'Plan created'
                        : r.attention
                        ? 'Order placed · Awaiting payment'
                        : 'Order confirmed',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: -0.3,
                      color: ShodashaTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (r.attention) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: ShodashaTheme.blueTint,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                ),
                child: Text(
                  r.attentionMessage,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: ShodashaTheme.border),
                borderRadius: BorderRadius.circular(ShodashaTheme.radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: ShodashaTheme.tealDeep,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          r.windowLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: ShodashaTheme.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (r.waterPaise > 0 || r.depositPaise > 0) ...[
                    Text(
                      'Water ${rupeesLabel(r.waterPaise)}'
                      '${r.depositPaise > 0 ? ' + Deposit ${rupeesLabel(r.depositPaise)}' : ''}'
                      '${r.capsPaise > 0 ? ' + Cap ${rupeesLabel(r.capsPaise)} (at handover)' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: ShodashaTheme.muted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  if (r.totalPaise > 0)
                    Text(
                      'Amount: ${rupeesLabel(r.totalPaise)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                  if (r.addressLabel.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: ShodashaTheme.muted,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            r.addressLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: ShodashaTheme.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  if (r.isSubscription)
                    const Text(
                      'No advance payment today · First delivery billed as usual',
                      style: TextStyle(
                        color: ShodashaTheme.muted,
                        fontSize: 12,
                      ),
                    )
                  else if (!r.attention)
                    Text(
                      r.payOnDelivery
                          ? 'Pay ${rupeesLabel(r.totalPaise)} in cash when rider arrives'
                          : 'Rider details will appear once assigned',
                      style: const TextStyle(
                        color: ShodashaTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (r.upiPending && !r.attention) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: ShodashaTheme.blueTint,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                ),
                child: const Text(
                  'UPI payment processing — status updates automatically in Orders.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
            if (r.isSubscription) ...[
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onOpenSubscriptions?.call();
                  },
                  child: const Text('Manage plan in Plans tab'),
                ),
              ),
            ],
            if (!r.attention) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: ShodashaTheme.tealTint,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: ShodashaTheme.tealDeep,
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Refundable safety deposit tracked securely in your Wallet',
                        style: TextStyle(fontSize: 12, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: r.isSubscription ? 'View plans' : 'Track order',
              kind: AppButtonKind.primary,
              onPressed: () => _primary(context),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              label: 'Done',
              kind: AppButtonKind.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            if (id.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Text(
                  r.isSubscription
                      ? 'Plan ref #${_shortRef(id)}'
                      : 'Order ref #${_shortRef(id)}',
                  style: const TextStyle(
                    color: ShodashaTheme.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
