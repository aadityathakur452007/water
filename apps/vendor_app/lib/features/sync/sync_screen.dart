// Sync screen: outbox queue + pending badge + per-stop resolve log.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/vendor_locale.dart';
import 'sync_controller.dart';


String _formatQueuedTime(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final diff = DateTime.now().toUtc().difference(dt.toUtc());
  if (diff.isNegative || diff.inSeconds < 60) {
    return vtr('अभी-अभी', 'Just now');
  } else if (diff.inMinutes < 60) {
    return vtr('${diff.inMinutes} मिनट पहले', '${diff.inMinutes}m ago');
  } else if (diff.inHours < 24) {
    return vtr('${diff.inHours} घंटे पहले', '${diff.inHours}h ago');
  } else {
    return vtr('${diff.inDays} दिन पहले', '${diff.inDays}d ago');
  }
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, required this.controller});

  final SyncController controller;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
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

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(vtr('सिंक स्थिति', 'Sync Log'))),
      body: _body(c),
    );
  }

  Widget _body(SyncController c) {
    // S12: loading is its own branch — never "Sab synced" while reading.
    if (!c.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (c.queue.isEmpty && c.rejected.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Sab synced — koi pending entry nahi',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (c.result != null)
          Card(
            shape: ShodashaTheme.shape,
            color: ShodashaTheme.blueTint,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (c.tone) {
                      SyncResultTone.networkError => Icons.cloud_off_outlined,
                      SyncResultTone.serverError => Icons.error_outline,
                      SyncResultTone.success || SyncResultTone.none =>
                        Icons.check_circle_outline,
                    },
                    size: 20,
                    color: switch (c.tone) {
                      SyncResultTone.networkError => ShodashaTheme.muted,
                      SyncResultTone.serverError => ShodashaTheme.danger,
                      SyncResultTone.success || SyncResultTone.none =>
                        ShodashaTheme.blue,
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(c.result!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ElevatedButton.icon(
          onPressed: c.syncing || c.queue.isEmpty
              ? null
              : () => c.syncNow(),
          icon: const Icon(Icons.sync),
          label: Text(c.syncing
              ? 'Sync ho raha…'
              : 'Abhi sync karein (${c.queue.length})'),
        ),
        const SizedBox(height: 12),
        for (final q in c.queue)
          Card(
            shape: ShodashaTheme.shape,
            child: ListTile(
              minTileHeight: ShodashaTheme.minTarget,
              leading: const Icon(Icons.pending_outlined,
                  color: ShodashaTheme.blue),
              title: Text('Stop ${q.stopId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '${q.triple['fulls_given'] ?? 0} diye • ${q.triple['empties_back'] ?? 0} wapas • ${_formatQueuedTime(q.queuedAtIso)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ),
        for (final r in c.rejected)
          Card(
            shape: ShodashaTheme.shape,
            child: ListTile(
              minTileHeight: ShodashaTheme.minTarget,
              leading: const Icon(Icons.error_outline,
                  color: ShodashaTheme.danger),
              title: Text('Rejected: ${r['stop_id'] ?? ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${r['code'] ?? ''} — ${r['message'] ?? ''}',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              // Phase 5 §5.5: stuck rejects (STALE_STOP) get a discard
              // path — the server already holds truth, the local replay
              // is what gets dropped.
              trailing: TextButton(
                onPressed: () =>
                    c.discardRejected((r['stop_id'] ?? '') as String),
                child: const Text('Hatayein'),
              ),
            ),
          ),
      ],
    );
  }
}
