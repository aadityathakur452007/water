// Stop detail: ledger snapshot (read-only server values) + qty due +
// entry points to triple and PoD sheets.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import 'pod_sheet.dart';
import 'stops_controller.dart';
import 'triple_sheet.dart';

class StopDetailScreen extends StatefulWidget {
  const StopDetailScreen({
    super.key,
    required this.controller,
    required this.stopId,
    required this.stopLabel,
  });

  final StopsController controller;
  final String stopId;
  final String stopLabel;

  @override
  State<StopDetailScreen> createState() => _StopDetailScreenState();
}

class _StopDetailScreenState extends State<StopDetailScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    widget.controller.load(widget.stopId);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.stopLabel)),
      body: _body(c),
    );
  }

  Widget _body(StopsController c) {
    if (c.state == StopDetailState.loading) {
      // Skeleton-ish boxes (same blueTint rhythm as route) — no new deps.
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            height: 96,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: ShodashaTheme.blueTint.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
          ),
          Container(
            height: 76,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: ShodashaTheme.blueTint.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
          ),
        ],
      );
    }
    if (c.state == StopDetailState.error ||
        c.state == StopDetailState.offline) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  size: 48, color: ShodashaTheme.muted),
              const SizedBox(height: 12),
              Text(c.error ?? 'Stop load nahi hua',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => c.load(widget.stopId),
                child: const Text('Dobara try karein'),
              ),
            ],
          ),
        ),
      );
    }
    final s = c.stop ?? {};
    final name =
        (s['customer_name'] ?? s['customer_id'] ?? 'Customer') as String;
    final phone = (s['customer_phone'] ?? '') as String;
    final address = (s['address_text'] ?? s['address'] ?? '') as String;
    final fullsExp = (s['fulls_exp'] as num?)?.toInt() ?? 0;
    final emptiesExp = (s['empties_exp'] as num?)?.toInt() ?? 0;
    final totalPaise = (s['total'] as num?)?.toInt() ??
        (s['cash_due'] as num?)?.toInt() ??
        0;
    final cashDue = totalPaise;
    final paymentMode = (s['payment_mode'] ?? 'cod') as String;
    final paymentStatus = (s['payment_status'] ?? 'unpaid') as String;
    final isPaid =
        paymentStatus == 'paid_upi' || paymentStatus == 'paid_cash';
    final held = (s['held'] as num?)?.toInt();
    final deposit = (s['deposit_balance'] as num?)?.toInt();
    final dues = (s['dues'] as num?)?.toInt();
    final holdBlocked = (s['hold_blocked'] as bool?) ?? false;
    if (c.notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(c.notice!)));
        c.clearNotice();
      });
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: ShodashaTheme.shape,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                // 015: payment badge — mode + paid/collect state (prominent,
                // amount only when server sent a total; never "Rs 0").
                Text(
                  isPaid
                      ? (totalPaise > 0
                          ? '${paymentMode.toUpperCase()} • Paid ${rupees(totalPaise)}'
                          : '${paymentMode.toUpperCase()} • Paid')
                      : (totalPaise > 0
                          ? '${paymentMode.toUpperCase()} • Collect ${rupees(totalPaise)}'
                          : paymentMode.toUpperCase()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: ShodashaTheme.blue,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
                if (address.isNotEmpty)
                  Text(address,
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                if (phone.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _call(phone),
                    icon: const Icon(Icons.call),
                    label: const Text('Call customer'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Ledger fact rows (bordered icon-lead shape): server-read-only
        // values, same texts, hairline border instead of a filled card.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: ShodashaTheme.border),
            borderRadius: BorderRadius.circular(ShodashaTheme.radius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                size: 18,
                color: ShodashaTheme.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '$fullsExp jars dene • $emptiesExp khaali expected • ${rupees(cashDue)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    // Ledger: only non-zero server values render — null and
                    // 0 never show as "-" or "Rs 0" (honest, no confusion).
                    if ((held != null && held > 0) ||
                        (deposit != null && deposit > 0) ||
                        (dues != null && dues > 0))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Ledger: ${[
                            if (held != null && held > 0) '$held held',
                            if (deposit != null && deposit > 0)
                              '${rupees(deposit)} deposit',
                            if (dues != null && dues > 0)
                              '${rupees(dues)} baaki',
                          ].join(' • ')}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(color: ShodashaTheme.muted),
                        ),
                      ),
                    if (holdBlocked)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Hold limit — pehle deposit, phir delivery',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: ShodashaTheme.danger),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: c.submitting || holdBlocked
              ? null
              : () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => TripleSheet(
                      controller: c,
                      stopId: widget.stopId,
                      fullsExp: fullsExp,
                      emptiesExp: emptiesExp,
                      collectPaise: totalPaise,
                      paymentMode: paymentMode,
                    ),
                  ),
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('Triple likhein: diye / wapas / paise'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: c.submitting
              ? null
              : () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => PodSheet(
                      controller: c,
                      stopId: widget.stopId,
                      collectPaise: totalPaise,
                      paymentMode: paymentMode,
                    ),
                  ),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('PoD: OTP se complete karein'),
        ),
      ],
    );
  }
}
