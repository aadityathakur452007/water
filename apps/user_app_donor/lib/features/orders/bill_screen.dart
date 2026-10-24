// Frozen bill view for one order. Every amount comes from the server; the
// client never recomputes a total or hides previous dues / payments.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart' show kSupportPhone;
import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_card.dart';
import '../../shared/ui/status_pill.dart';
import 'orders_controller.dart';

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ordersStringsHi['whatsappFail']!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(
        backgroundColor: ShodashaTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: ShodashaTheme.border)),
        leadingWidth: 56,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded, color: ShodashaTheme.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Bill · #${o.id}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: ShodashaTheme.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (o.refundPending) ...[
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  color: ShodashaTheme.blueTint,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: ShodashaTheme.blue,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '${ordersStringsHi['refundPending']!} • '
                          '${formatRupees(o.refundAmountPaise)}',
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: ShodashaTheme.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              AppCard(
                child: Column(
                  children: [
                    _Line(
                      label: 'Water',
                      amount: formatRupees(o.waterBillPaise),
                    ),
                    _Line(
                      label: 'Jar deposit',
                      amount: formatRupees(o.depositDuePaise),
                    ),
                    if (o.capChargePaise > 0)
                      _Line(
                        label: 'Cap charge',
                        amount: formatRupees(o.capChargePaise),
                      ),
                    if (o.prevDuesPaise != 0)
                      _Line(
                        label: 'Previous dues',
                        amount: formatRupees(o.prevDuesPaise),
                      ),
                    if (o.paymentsPaise != 0)
                      _Line(
                        label: 'Payment received',
                        amount: '−${formatRupees(o.paymentsPaise)}',
                      ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Divider(height: 1, color: ShodashaTheme.border),
                    ),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Total',
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
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: ShodashaTheme.ink,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        StatusPill(
                          label: o.paymentLabel,
                          tone: o.isPaid
                              ? StatusPillTone.success
                              : o.paymentStatus == 'partial_dues'
                              ? StatusPillTone.warning
                              : StatusPillTone.neutral,
                          icon: o.isPaid
                              ? Icons.check_circle_outline
                              : Icons.payments_outlined,
                        ),
                        const Spacer(),
                        Text(
                          o.state == OrderState.delivered
                              ? 'Bill frozen at delivery'
                              : 'Final bill is confirmed after delivery',
                          style: const TextStyle(
                            fontSize: 11,
                            color: ShodashaTheme.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (o.prevDuesPaise > 0) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  ordersStringsHi['duesNote']!,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: ShodashaTheme.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: ordersStringsHi['whatsappHelp']!,
                kind: AppButtonKind.secondary,
                icon: Icons.share_outlined,
                onPressed: () => _share(context, o),
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: ShodashaTheme.muted,
                fontWeight: FontWeight.w500,
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
