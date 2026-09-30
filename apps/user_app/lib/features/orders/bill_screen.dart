// F4 — Bill screen (paise ints, frozen refund-pending, WhatsApp share stub).
// Contract §4.4 + user-flows flow 5 (bill = water + deposit + cap + dues −
// payments; partials carried, never silently zeroed; COD flips on vendor
// sync). Refund-pending lines are display-only: the frozen total never
// recomputes on the client.

import 'package:flutter/material.dart';

import 'orders_controller.dart';

/// Frozen bill view for one [Order].
class BillScreen extends StatelessWidget {
  const BillScreen({super.key, required this.order});

  final Order order;

  Future<void> _share(BuildContext context) async {
    // TODO(F1): wa.me share with prefilled bill text via url_launcher.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ordersStringsHi['whatsappFail']!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Scaffold(
      backgroundColor: OrdersTokens.white,
      appBar: AppBar(
        backgroundColor: OrdersTokens.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: OrdersTokens.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '#${o.id}',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: OrdersTokens.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (o.refundPending)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: OrdersTokens.blueTint,
                    borderRadius:
                        BorderRadius.circular(OrdersTokens.radius),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: OrdersTokens.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${ordersStringsHi['refundPending']!} • '
                          '${formatRupees(o.refundAmountPaise)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: OrdersTokens.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (o.refundPending) const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: OrdersTokens.white,
                  border: Border.all(color: OrdersTokens.border),
                  borderRadius:
                      BorderRadius.circular(OrdersTokens.radius),
                ),
                child: Column(
                  children: [
                    _Line(
                      label: 'Paani',
                      amount: formatRupees(o.waterBillPaise),
                    ),
                    _Line(
                      label: 'Deposit',
                      amount: formatRupees(o.depositDuePaise),
                    ),
                    if (o.capChargePaise > 0)
                      _Line(
                        label: 'Cap',
                        amount: formatRupees(o.capChargePaise),
                      ),
                    if (o.prevDuesPaise != 0)
                      _Line(
                        label: 'Pichla baki',
                        amount: formatRupees(o.prevDuesPaise),
                      ),
                    if (o.paymentsPaise != 0)
                      _Line(
                        label: 'Bhugtan',
                        amount: '−${formatRupees(o.paymentsPaise)}',
                      ),
                    const Divider(color: OrdersTokens.border, height: 24),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Kul',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: OrdersTokens.ink,
                            ),
                          ),
                        ),
                        Text(
                          formatRupees(o.totalPaise),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: OrdersTokens.ink,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (o.prevDuesPaise > 0) ...[
                const SizedBox(height: 12),
                Text(
                  ordersStringsHi['duesNote']!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: OrdersTokens.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: OrdersTokens.minTarget,
                child: ElevatedButton(
                  onPressed: () => _share(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OrdersTokens.blue,
                    foregroundColor: OrdersTokens.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(OrdersTokens.radius),
                    ),
                  ),
                  child: Text(ordersStringsHi['whatsappHelp']!),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.amount});
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: OrdersTokens.muted,
              ),
            ),
          ),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: OrdersTokens.ink,
            ),
          ),
        ],
      ),
    );
  }
}
