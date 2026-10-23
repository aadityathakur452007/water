// Donor order card, mapped onto the real 032 Order model.
//
// Removed from the donor version: the local delivery-code block, the hardcoded
// rider/van name, and the "rider enter PIN & deliver" button (a customer app
// must never be able to complete a delivery). The only actions here are
// Track / View bill; the server owns status and PoD. 034: the list endpoint
// never carries the delivery code, so this card must not render one — the
// secret lives only on tracking.

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/money.dart';
import 'orders_controller.dart';

class DonorOrderCard extends StatelessWidget {
  const DonorOrderCard({
    super.key,
    required this.order,
    required this.onTrack,
    required this.onBill,
  });

  final Order order;
  final VoidCallback onTrack;
  final VoidCallback onBill;

  bool get _isDelivered => order.state == OrderState.delivered;
  bool get _isClosed =>
      _isDelivered ||
      order.state == OrderState.cancelled ||
      order.state == OrderState.rejected ||
      order.state == OrderState.failed;

  String get _title {
    final bits = <String>[];
    if (order.refillQty > 0) {
      bits.add('${order.refillQty} x 20L Refill');
    }
    if (order.containerQty > 0) {
      bits.add('${order.containerQty} x 20L New Jar');
    }
    if (bits.isNotEmpty) return bits.join(' + ');
    final summary = order.itemSummary.trim();
    return summary.isEmpty ? 'Water order' : summary;
  }

  int get _qty {
    final qty = order.refillQty + order.containerQty;
    return qty > 0 ? qty : 1;
  }

  String get _window {
    final start = order.windowStart;
    final end = order.windowEnd;
    String two(int n) => n.toString().padLeft(2, '0');
    final startLabel = '${two(start.hour)}:${two(start.minute)}';
    if (end == null) return startLabel;
    return '$startLabel - ${two(end.hour)}:${two(end.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _isDelivered
        ? const Color(0xFF15803D)
        : _isClosed
        ? const Color(0xFF64748B)
        : const Color(0xFF854D0E);
    final statusBg = _isDelivered
        ? const Color(0xFFDCFCE7)
        : _isClosed
        ? const Color(0xFFF1F5F9)
        : const Color(0xFFFEF9C3);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isDelivered ? const Color(0xFFDCFCE7) : AppColors.border,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '#${order.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppColors.primary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  order.state.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.water_drop,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'QTY: $_qty ${_qty > 1 ? "CANS" : "CAN"}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                              letterSpacing: 0.2,
                              color: Color(0xFF0369A1),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatInr(order.totalPaise),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.schedule,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                _window,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                order.isPaid ? Icons.verified : Icons.payments_outlined,
                size: 14,
                color: order.isPaid
                    ? const Color(0xFF15803D)
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                order.isPaid
                    ? 'Paid'
                    : order.paymentMode == 'upi'
                    ? 'UPI pending'
                    : 'Cash on delivery',
                style: TextStyle(
                  fontSize: 11.5,
                  color: order.isPaid
                      ? const Color(0xFF15803D)
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (order.addressLabel.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.addressLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isClosed
                    ? const Color(0xFFF1F5F9)
                    : AppColors.money,
                foregroundColor: _isClosed
                    ? AppColors.textPrimary
                    : Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _isClosed ? onBill : onTrack,
              icon: Icon(
                _isClosed ? Icons.receipt_long : Icons.local_shipping_outlined,
                size: 16,
              ),
              label: Text(
                _isClosed ? 'VIEW BILL' : 'TRACK ORDER',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
