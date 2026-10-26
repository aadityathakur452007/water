// Donor order card, mapped onto the real 032 Order model.
//
// The list endpoint never carries the delivery code, so this card cannot
// render one. Actions are Track / View bill (plus a help path for rejected
// orders); the server owns status, payment truth and PoD.

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_card.dart';
import '../../shared/ui/status_pill.dart';
import 'orders_controller.dart';

class DonorOrderCard extends StatelessWidget {
  const DonorOrderCard({
    super.key,
    required this.order,
    required this.onTrack,
    required this.onBill,
    this.onSupport,
  });

  final Order order;
  final VoidCallback onTrack;
  final VoidCallback onBill;
  final VoidCallback? onSupport;

  bool get _isDelivered => order.state == OrderState.delivered;
  bool get _isClosed =>
      _isDelivered ||
      order.state == OrderState.cancelled ||
      order.state == OrderState.rejected ||
      order.state == OrderState.failed;

  bool get _needsHelp =>
      order.state == OrderState.rejected || order.state == OrderState.failed;

  String get _title {
    final bits = <String>[];
    if (order.refillQty > 0) {
      bits.add('${order.refillQty} × 20L refill');
    }
    if (order.containerQty > 0) {
      bits.add('${order.containerQty} × 20L new jar');
    }
    if (bits.isNotEmpty) return bits.join(' + ');
    final summary = order.itemSummary.trim();
    return summary.isEmpty ? 'Water order' : summary;
  }

  int get _qty {
    final qty = order.refillQty + order.containerQty;
    return qty > 0 ? qty : 1;
  }

  bool get _hasWindow => order.windowStart.year > 2000;

  String get _window {
    final start = order.windowStart;
    final end = order.windowEnd;
    String two(int n) => n.toString().padLeft(2, '0');
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day =
        '${days[start.weekday - 1]}, ${start.day} ${months[start.month - 1]}';
    final from = '${two(start.hour)}:${two(start.minute)}';
    if (end == null) return '$day · from $from';
    return '$day · $from–${two(end.hour)}:${two(end.minute)}';
  }

  (StatusPillTone, IconData) get _statusTone => switch (order.state) {
    OrderState.delivered => (
      StatusPillTone.success,
      Icons.check_circle_outline,
    ),
    OrderState.cancelled => (StatusPillTone.neutral, Icons.block_outlined),
    OrderState.rejected ||
    OrderState.failed => (StatusPillTone.danger, Icons.error_outline),
    OrderState.dispatched || OrderState.assigned => (
      StatusPillTone.warning,
      Icons.local_shipping_outlined,
    ),
    _ => (StatusPillTone.info, Icons.schedule_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = _statusTone;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${order.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: ShodashaTheme.muted,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                StatusPill(
                  label: orderStateLabel(order.state),
                  tone: tone,
                  icon: icon,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: ShodashaTheme.ink,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ShodashaTheme.tealTint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_qty × 20L',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: ShodashaTheme.tealDeep,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  formatInr(order.totalPaise),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: ShodashaTheme.ink,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Divider(height: 1, color: ShodashaTheme.border),
            ),
            _MetaRow(
              icon: Icons.schedule_outlined,
              text: _hasWindow ? _window : 'Delivery window to be confirmed',
            ),
            const SizedBox(height: AppSpacing.xs),
            _MetaRow(
              icon: order.isPaid
                  ? Icons.check_circle_outline
                  : Icons.payments_outlined,
              text: order.paymentLabel,
              color: order.isPaid
                  ? ShodashaTheme.successDark
                  : ShodashaTheme.muted,
            ),
            if (order.addressLabel.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              _MetaRow(
                icon: Icons.location_on_outlined,
                text: order.addressLabel,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            if (_needsHelp && onSupport != null)
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'View bill',
                      kind: AppButtonKind.secondary,
                      onPressed: onBill,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppButton(
                      label: 'Get help',
                      kind: AppButtonKind.ghost,
                      onPressed: onSupport,
                    ),
                  ),
                ],
              )
            else if (_isClosed)
              Row(
                children: [
                  Expanded(
                    child: AppButton(label: 'View bill', onPressed: onBill),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppButton(
                      label: 'View details',
                      kind: AppButtonKind.secondary,
                      onPressed: onTrack,
                    ),
                  ),
                ],
              )
            else
              AppButton(
                label: 'Track order',
                icon: Icons.local_shipping_outlined,
                onPressed: onTrack,
              ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.text,
    this.color = ShodashaTheme.muted,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
