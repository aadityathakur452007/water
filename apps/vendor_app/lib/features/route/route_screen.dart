// Today route sheet: loading header + sequenced stop cards + SKIP list.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cascade.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import 'route_controller.dart';

class RouteScreen extends StatefulWidget {
  const RouteScreen({
    super.key,
    required this.controller,
    required this.onOpenStop,
    this.onOpenCustomers,
    this.onOpenSync,
  });

  final RouteController controller;
  final void Function(RouteStop stop) onOpenStop;

  /// Drawer destinations surfaced as Route sections (Wave 1 shell merge).
  final VoidCallback? onOpenCustomers;
  final VoidCallback? onOpenSync;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    widget.controller.load();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
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

  Widget _body(RouteController c) {
    switch (c.state) {
      case RouteState.loading:
        return const Center(child: CircularProgressIndicator());
      case RouteState.empty:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aaj koi stop nahi — duty on karke dobara dekhein',
              textAlign: TextAlign.center,
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

  Widget _stopCard(RouteStop s, {bool greyed = false}) {
    return Opacity(
      opacity: greyed ? 0.55 : 1.0,
      // Bordered fact-row shape (reference CustomCard rhythm): seq avatar
      // lead, name + facts, status/nav trailing. Hairline border, no shadow.
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: ShodashaTheme.border),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        child: ListTile(
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
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '${s.fullsExpected} jars • ${s.emptiesExpected} khaali expected • ${rupees(s.cashDuePaise)}'),
              if (s.address.isNotEmpty)
                Text(s.address,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              if (s.holdBlocked)
                Text(
                  s.holdReason ?? 'Hold limit — deposit mangein',
                  style: const TextStyle(color: ShodashaTheme.danger),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (s.isDone)
                const Icon(Icons.check_circle,
                    color: ShodashaTheme.success),
              if (s.address.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.navigation_outlined,
                      color: ShodashaTheme.blue),
                  tooltip: 'Navigate karein',
                  onPressed: () => _navigate(s.address),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
