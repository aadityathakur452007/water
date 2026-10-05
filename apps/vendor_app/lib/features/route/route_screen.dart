// Today route sheet: loading header + sequenced stop cards + SKIP list.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cascade.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../customers/customers_controller.dart';
import '../earnings/earnings_controller.dart';
import 'route_controller.dart';

class RouteScreen extends StatefulWidget {
  const RouteScreen({
    super.key,
    required this.controller,
    required this.onOpenStop,
    this.onOpenCustomers,
    this.onOpenSync,
    this.earnings,
    this.customers,
  });

  final RouteController controller;
  final void Function(RouteStop stop) onOpenStop;

  /// Drawer destinations surfaced as Route sections (Wave 1 shell merge).
  final VoidCallback? onOpenCustomers;
  final VoidCallback? onOpenSync;

  /// 016 dashboard: inline money (c) + can-ledger (d) reuse the tab
  /// controllers — no new fetch shape, no new endpoint.
  final EarningsController? earnings;
  final CustomersController? customers;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    widget.controller.load();
    // 016: dashboard sections share the tab controllers. One load per
    // screen lifetime; tab visits refetch as before (existing behavior).
    widget.earnings?.addListener(_onChange);
    widget.customers?.addListener(_onChange);
    widget.earnings?.load();
    widget.customers?.load();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    widget.earnings?.removeListener(_onChange);
    widget.customers?.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _navigate(String address) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aaj ka route'),
        actions: [
          if (widget.onOpenCustomers != null)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Customers khojein',
              onPressed: widget.onOpenCustomers,
            ),
          if (c.pendingSync > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                backgroundColor: ShodashaTheme.blueTint,
                label: Text('Sync baaki (${c.pendingSync})'),
                onPressed: widget.onOpenSync,
              ),
            ),
        ],
      ),
      body: _body(c),
    );
  }

  Future<void> _pullPlaced(RouteController c) async {
    final n = await c.refreshPlaced();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n > 0
            ? '$n placed orders — dispatch se assign karvayein'
            : 'Koi naya placed order nahi')));
  }

  Widget _body(RouteController c) {
    switch (c.state) {
      case RouteState.loading:
        // 015 premium: skeleton cards instead of bare spinner.
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                height: 76,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: ShodashaTheme.blueTint.withValues(alpha: 0.5),
                  borderRadius:
                      BorderRadius.circular(ShodashaTheme.radius),
                ),
              ),
          ],
        );
      case RouteState.empty:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Aaj koi stop nahi — duty on karke dobara dekhein',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => c.load(),
                  child: const Text('Dobara try karein'),
                ),
              ],
            ),
          ),
        );
      case RouteState.offline:
      case RouteState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  c.state == RouteState.offline
                      ? Icons.cloud_off_outlined
                      : Icons.error_outline,
                  size: 48,
                  color: ShodashaTheme.muted,
                ),
                const SizedBox(height: 12),
                Text(c.error ?? 'Route load nahi hua',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => c.load(),
                  child: const Text('Dobara try karein'),
                ),
              ],
            ),
          ),
        );
      case RouteState.loaded:
        break;
    }
    return RefreshIndicator(
      onRefresh: () => c.load(),
      child: CascadeScope(
        itemCount: c.stops.length + c.skipped.length,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 016 dashboard: today strip + one CTA + money + can ledger.
            _todayStrip(c),
            const SizedBox(height: 12),
            // 015: Pull placed pool (simple — no geo/auto-assign).
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _pullPlaced(c),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text(c.placed.isEmpty
                    ? 'Placed orders kheenchein'
                    : 'Placed (${c.placed.length}) — dispatch se assign'),
              ),
            ),
            const SizedBox(height: 12),
            // Loading-sheet header row (section-header rhythm): label left,
            // done/total right, facts below. Same controller data, no tint.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: ShodashaTheme.border),
                borderRadius:
                    BorderRadius.circular(ShodashaTheme.radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Loading sheet',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      Text(
                        '${c.doneCount}/${c.stops.length}',
                        style: const TextStyle(
                            color: ShodashaTheme.muted, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${c.takeFulls} fulls lein • ${c.expectEmpties} khaali expected',
                    style: const TextStyle(
                        color: ShodashaTheme.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < c.stops.length; i++)
              CascadeItem(index: i, child: _stopCard(c.stops[i])),
            if (c.skipped.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('SKIP (pause/late)',
                      style: TextStyle(
                          color: ShodashaTheme.muted,
                          fontWeight: FontWeight.w600)),
                  Text(
                    '${c.skipped.length}',
                    style: const TextStyle(
                        color: ShodashaTheme.muted, fontSize: 13),
                  ),
                ],
              ),
              for (var i = 0; i < c.skipped.length; i++)
                CascadeItem(
                  index: c.stops.length + i,
                  child: _stopCard(c.skipped[i], greyed: true),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 016 dashboard §3(a): one banner strip + ONE primary CTA per state.
  /// States: outbox non-empty → Sync; else first pending stop → Triple;
  /// else all done → honest text, no fake action. Black 48dp CTA only.
  Widget _todayStrip(RouteController c) {
    final s = summarizeToday(c.stops);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Aaj ka hisaab',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text('${s.done}/${s.total}',
                  style: const TextStyle(
                      color: ShodashaTheme.muted, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${s.users} grahak · ${s.jars} jars',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: ShodashaTheme.muted, fontSize: 13),
          ),
          Text(
            'Collect ${rupees(s.collect)} (UPI ${rupees(s.upiCollect)} · COD ${rupees(s.codCollect)})',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _dashboardCta(c),
          _moneyRow(),
          _ledgerRows(),
        ],
      ),
    );
  }

  Widget _dashboardCta(RouteController c) {
    if (c.pendingSync > 0 && widget.onOpenSync != null) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: widget.onOpenSync,
          icon: const Icon(Icons.sync_outlined, size: 18),
          label: Text('Sync karein (${c.pendingSync} baaki)'),
        ),
      );
    }
    final pending = c.stops.where((s) => !s.isDone && !s.isFailed).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    if (pending.isNotEmpty) {
      final first = pending.first;
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => widget.onOpenStop(first),
          icon: const Icon(Icons.inventory_2_outlined, size: 18),
          label: Text('Triple: ${first.customerName}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    return const Text('Sab stops done — badhai',
        style: TextStyle(color: ShodashaTheme.success, fontSize: 13));
  }

  /// 016 §3(c): inline money, display-only server paise. Shown only when
  /// the earnings controller actually loaded — never invented, never Rs 0
  /// for missing data (real server zeros do render: they are truth).
  Widget _moneyRow() {
    final e = widget.earnings;
    if (e == null || e.state != EarningsState.loaded) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Jama ${rupees(e.cashTotal + e.upiTotal)} '
            '(Cash ${rupees(e.cashTotal)} + UPI ${rupees(e.upiTotal)})',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          if (e.flaggedHold > 0)
            Text('${e.flaggedStops} stops review me — ${rupees(e.flaggedHold)} hold par',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: ShodashaTheme.danger, fontSize: 12)),
          const Text('Sirf jankari — payout admin clear ke baad.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ShodashaTheme.muted, fontSize: 12)),
        ],
      ),
    );
  }

  /// 016 §3(d): per-customer can ledger. Only customers with held>0 or
  /// dues>0 render (Q2: zero rows hidden honestly); section hidden when
  /// empty or still loading.
  Widget _ledgerRows() {
    final cu = widget.customers;
    if (cu == null || cu.state != CustomersState.loaded) {
      return const SizedBox.shrink();
    }
    final flagged =
        cu.items.where((v) => v.held > 0 || v.duesPaise > 0).toList();
    if (flagged.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Can ledger',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          for (final v in flagged)
            Text(
              '${v.name} — ${[
                if (v.held > 0) '${v.held} held',
                if (v.duesPaise > 0) '${rupees(v.duesPaise)} baaki',
              ].join(' · ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(color: ShodashaTheme.muted, fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _stopCard(RouteStop s, {bool greyed = false}) {
    final failed = s.isFailed;
    return Opacity(
      opacity: greyed || failed ? 0.55 : 1.0,
      // Bordered fact-row shape (reference CustomCard rhythm): seq avatar
      // lead, name + facts, status/nav trailing. Hairline border, no shadow.
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: ShodashaTheme.border),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        child: ListTile(
          minTileHeight: ShodashaTheme.minTarget,
          onTap: greyed ? null : () => widget.onOpenStop(s),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: s.isDone
                ? ShodashaTheme.success
                : ShodashaTheme.ink,
            foregroundColor: ShodashaTheme.bg,
            child: Text('${s.seq}'),
          ),
          title: Text(s.customerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // F8: pickup stops show jars-to-collect, not delivery facts.
              Text(
                  s.returnId.isNotEmpty
                      ? 'Khaali pickup • ${s.emptiesExpected} jars wapas lein'
                      : '${s.fullsExpected} jars • ${s.emptiesExpected} khaali expected • ${rupees(s.totalPaise > 0 ? s.totalPaise : s.cashDuePaise)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              // 015: payment mode + paid state badge (delivery stops only).
              if (s.returnId.isEmpty)
                Text(
                  s.isPaid
                      ? '${s.paymentMode.toUpperCase()} • Paid'
                      : '${s.paymentMode.toUpperCase()} • Collect ${rupees(s.totalPaise > 0 ? s.totalPaise : s.cashDuePaise)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: ShodashaTheme.blue, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              if (s.address.isNotEmpty)
                Text(s.address,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              if (s.holdBlocked)
                Text(
                  s.holdReason ?? 'Hold limit — deposit mangein',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: ShodashaTheme.danger),
                ),
              if (failed)
                const Text(
                  'Failed — admin dobara assign karega',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ShodashaTheme.danger),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (s.isDone)
                const Icon(Icons.check_circle,
                    color: ShodashaTheme.success),
              if (failed)
                const Icon(Icons.error_outline,
                    color: ShodashaTheme.danger),
              if (s.address.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.navigation_outlined,
                      color: ShodashaTheme.blue),
                  tooltip: 'Navigate karein',
                  constraints: const BoxConstraints(
                      minWidth: 48, minHeight: 48),
                  onPressed: () => _navigate(s.address),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
