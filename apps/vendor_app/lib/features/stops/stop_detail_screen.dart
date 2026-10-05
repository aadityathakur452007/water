// Stop detail: ledger snapshot (read-only server values) + qty due +
// entry points to triple and PoD sheets.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../sync/sync_controller.dart';
import 'pod_sheet.dart';
import 'stops_controller.dart';
import 'triple_sheet.dart';

class StopDetailScreen extends StatefulWidget {
  const StopDetailScreen({
    super.key,
    required this.controller,
    required this.stopId,
    required this.stopLabel,
    this.outbox,
  });

  final StopsController controller;
  final String stopId;
  final String stopLabel;

  /// Offline outbox (F2 cash ride + offline triple queue).
  final SyncController? outbox;

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

  /// F2 cash post; offline queues triple+cash into the outbox (sync replays
  /// the triple as a no-op then posts cash — server dedupes both). Posts the
  /// live remainder (partial orders) so the server OVERPAY guard never trips.
  Future<void> _postCash(StopsController c, int amountPaise) async {
    final orderId = (c.stop?['order_id'] ?? '') as String;
    final due = orderId.isNotEmpty ? await c.amountDue(orderId) : null;
    final amount = (due != null && due > 0) ? due : amountPaise;
    final ok = await c.postCash(
        stopId: widget.stopId, amountPaise: amount);
    if (!ok && c.lastWasNetwork && widget.outbox != null) {
      final triple = c.stop?['triple'];
      if (triple is Map<String, dynamic>) {
        await widget.outbox!.enqueue(
          stopId: widget.stopId,
          triple: {...triple, 'version': c.version},
          cashAmountPaise: amountPaise,
        );
      }
    }
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
    // Phase 5 §5.2: same predicates as the route list (copied, not shared).
    final isPaid =
        paymentStatus == 'paid_upi' || paymentStatus == 'paid_cash';
    final isPartial = paymentStatus == 'partial_dues';
    final isLinkSent = paymentStatus == 'link_sent';
    final paidSum = (s['paid_sum'] as num?)?.toInt() ?? 0;
    int remaining() {
      if (isPaid || isLinkSent) return 0;
      if (!isPartial) return totalPaise;
      final left = totalPaise - paidSum;
      return left > 0 ? left : 0;
    }

    final remainingPaise = remaining();
    // Phase 5 §5.5: required-action gating — PoD needs a saved triple;
    // a finished stop shows the done note, never action buttons.
    final tripleDone = s['triple'] is Map;
    final stopDone = (s['status'] ?? '') == 'done';
    final orderLabel = orderStateLabelHi((s['order_state'] ?? '') as String);
    final held = (s['held'] as num?)?.toInt();
    final deposit = (s['deposit_balance'] as num?)?.toInt();
    final dues = (s['dues'] as num?)?.toInt();
    final holdBlocked = (s['hold_blocked'] as bool?) ?? false;
    final returnId = (s['return_id'] ?? '') as String;
    final windowStart = (s['window_start'] ?? '') as String;
    final instructions = (s['instructions'] ?? '') as String;
    final items = (s['items'] is List)
        ? (s['items'] as List)
            .whereType<Map<String, dynamic>>()
            .map((e) => '${e['qty'] ?? 0} ${e['sku'] ?? ''}'.trim())
            .where((e) => e.isNotEmpty && e != '0')
            .join(' • ')
        : '';
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
                // Phase 5 §5.2: partial shows the remainder; a sent UPI
                // link asks for verification, never cash.
                Text(
                  isPaid
                      ? (totalPaise > 0
                          ? '${paymentMode.toUpperCase()} • Paid ${rupees(totalPaise)}'
                          : '${paymentMode.toUpperCase()} • Paid')
                      : isLinkSent
                          ? '${paymentMode.toUpperCase()} • UPI link bheja, verify karein'
                          : isPartial
                              ? '${paymentMode.toUpperCase()} • Collect ${rupees(remainingPaise)} (baaki)'
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
                if (windowStart.isNotEmpty)
                  Text('Window: $windowStart',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                if (items.isNotEmpty)
                  Text(items,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                if (instructions.isNotEmpty)
                  Text('Note: $instructions',
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                // Phase 5 §5.5: pipeline state as a Hindi what-it-means
                // line (unknown states hide — raw text never shows).
                if (orderLabel.isNotEmpty)
                  Text(orderLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: ShodashaTheme.muted)),
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
        // Phase 5 §5.5: required-action ordering — Triple → PoD → Cash,
        // gated by state with "pehle X karein" hints instead of
        // all-rendered. A finished stop shows the done note only.
        if (stopDone)
          const Text('Delivery complete / ho gayi',
              style: TextStyle(fontWeight: FontWeight.w600)),
        // F8: pickup stops act on the return, not the triple/PoD flow.
        if (!stopDone && returnId.isNotEmpty)
          _PickupCard(
            controller: c,
            stopId: widget.stopId,
            returnId: returnId,
            emptiesExp: emptiesExp,
          ),
        if (!stopDone && returnId.isEmpty && !tripleDone)
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
                        outbox: widget.outbox,
                        collectPaise: remainingPaise,
                        paymentMode: paymentMode,
                      ),
                    ),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Triple likhein: diye / wapas / paise'),
          ),
        if (!stopDone && returnId.isEmpty && tripleDone)
          const Text('Triple ho gayi — PoD karein',
              style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (!stopDone && returnId.isEmpty && tripleDone)
          OutlinedButton.icon(
            onPressed: c.submitting
                ? null
                : () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => PodSheet(
                        controller: c,
                        stopId: widget.stopId,
                        outbox: widget.outbox,
                        collectPaise: remainingPaise,
                        paymentMode: paymentMode,
                      ),
                    ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('PoD: OTP se complete karein'),
          ),
        if (!stopDone && returnId.isEmpty && !tripleDone)
          const Text('PoD ke liye pehle triple likhein',
              style: TextStyle(color: ShodashaTheme.muted)),
        // F2: one-tap cash post (COD delivery stops only, remainder due).
        // Paid/link-sent hide this; partial posts the remainder (the
        // server OVERPAY guard still enforces races).
        if (!stopDone &&
            returnId.isEmpty &&
            paymentMode != 'upi' &&
            !isLinkSent &&
            remainingPaise > 0) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: c.submitting
                ? null
                : () => _postCash(c, remainingPaise),
            icon: const Icon(Icons.payments_outlined),
            label: Text('Cash jama karein (${rupees(remainingPaise)})'),
          ),
        ],
        if (!stopDone && isLinkSent)
          const Text('UPI link bheja — cash na lein, payment verify karein',
              style: TextStyle(color: ShodashaTheme.muted)),
      ],
    );
  }
}

/// F8: empty-jar pickup card — steppers for collected/caps + one-tap post.
class _PickupCard extends StatefulWidget {
  const _PickupCard({
    required this.controller,
    required this.stopId,
    required this.returnId,
    required this.emptiesExp,
  });

  final StopsController controller;
  final String stopId;
  final String returnId;
  final int emptiesExp;

  @override
  State<_PickupCard> createState() => _PickupCardState();
}

class _PickupCardState extends State<_PickupCard> {
  late int _empties;
  int _caps = 0;

  @override
  void initState() {
    super.initState();
    _empties = widget.emptiesExp;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Khaali pickup: ${widget.emptiesExp} jars expected',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Row(
            children: [
              const Expanded(child: Text('Khaali mile')),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                iconSize: 32,
                constraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _empties > 0
                    ? () => setState(() => _empties--)
                    : null,
              ),
              Text('$_empties',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: ShodashaTheme.blue),
                iconSize: 32,
                constraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _empties < widget.emptiesExp
                    ? () => setState(() => _empties++)
                    : null,
              ),
            ],
          ),
          Row(
            children: [
              const Expanded(child: Text('Bina dhakkan (Rs 3/jar)')),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                iconSize: 32,
                constraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed:
                    _caps > 0 ? () => setState(() => _caps--) : null,
              ),
              Text('$_caps',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: ShodashaTheme.blue),
                iconSize: 32,
                constraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => setState(() => _caps++),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: c.submitting
                ? null
                : () => c.completePickup(
                      returnId: widget.returnId,
                      stopId: widget.stopId,
                      emptiesCollected: _empties,
                      capsMissing: _caps,
                    ),
            icon: const Icon(Icons.recycling_outlined),
            label: const Text('Pickup complete karein'),
          ),
        ],
      ),
    );
  }
}
