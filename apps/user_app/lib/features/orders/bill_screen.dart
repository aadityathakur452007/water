// S5 — Bill screen (paise ints, frozen refund-pending, WhatsApp share).
// Contract §4.4 + user-flows flow 5 (bill = water + deposit + cap + dues −
// payments; partials carried, never silently zeroed; COD flips on vendor
// sync). Refund-pending lines are display-only: the frozen total never
// recomputes on the client — every value is server-returned.
//
// Ported from apps/user_app_legacy_flutter F4; donor card grammar only.
// States.md covered: data available, refund pending, paid/due modes,
// secondary share action failure.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart' show kSupportPhone;
import '../../core/theme.dart';
import 'orders_controller.dart';

/// Frozen bill view for one [Order].
class BillScreen extends StatelessWidget {
  const BillScreen({super.key, required this.order});

  final Order order;

  /// Bill share = secondary wa.me link (never a post-purchase primary).
  Future<void> _share(BuildContext context, Order o) async {
    final text = 'Shodasha #${o.id} • ${formatRupees(o.totalPaise)}';
    final digits = kSupportPhone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse(
      'https://wa.me/$digits?text=${Uri.encodeComponent(text)}',
    );
    bool ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ordersStringsHi['whatsappFail']!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(
        backgroundColor: ShodashaTheme.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: ShodashaTheme.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '#${o.id}',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: ShodashaTheme.ink,
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
                    color: ShodashaTheme.blueTint,
                    borderRadius:
                        BorderRadius.circular(ShodashaTheme.radius),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: ShodashaTheme.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${ordersStringsHi['refundPending']!} • '
                          '${formatRupees(o.refundAmountPaise)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ShodashaTheme.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (o.refundPending) const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ShodashaTheme.surface,
                  border: Border.all(color: ShodashaTheme.border),
                  borderRadius:
                      BorderRadius.circular(ShodashaTheme.radiusLg),
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
                      )
                    else
                      const _Line(label: 'Cap', amount: '—'),
                    if (o.prevDuesPaise != 0)
                      _Line(
                        label: 'Previous dues',
                        amount: formatRupees(o.prevDuesPaise),
                      )
                    else
                      const _Line(label: 'Previous dues', amount: '—'),
                    if (o.paymentsPaise != 0)
                      _Line(
                        label: 'Payment',
                        amount: '−${formatRupees(o.paymentsPaise)}',
                      )
                    else
                      const _Line(label: 'Payment', amount: '—'),
                    // 015: payment mode + vendor-collect note (trust by visibility).
                    _Line(
                      label: 'Mode',
                      amount: o.isPaid
                          ? '${o.paymentMode.toUpperCase()} • Paid'
                          : '${o.paymentMode.toUpperCase()} • Due',
                    ),
                    const Divider(color: ShodashaTheme.border, height: 24),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Kul',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: ShodashaTheme.ink,
                            ),
                          ),
                        ),
                        Text(
                          formatRupees(o.totalPaise),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ShodashaTheme.ink,
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
                    color: ShodashaTheme.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: ShodashaTheme.minTarget,
                child: OutlinedButton.icon(
                  onPressed: () => _share(context, o),
                  icon: const Icon(Icons.share),
                  label: Text(ordersStringsHi['whatsappHelp']!),
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
                color: ShodashaTheme.muted,
              ),
            ),
          ),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ShodashaTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}
