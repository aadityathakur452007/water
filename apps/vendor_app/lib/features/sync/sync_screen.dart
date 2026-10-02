// Sync screen: outbox queue + pending badge + per-stop resolve log.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'sync_controller.dart';

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
      appBar: AppBar(title: const Text('Sync / सिंक')),
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
              child: Text(c.result!,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
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
              leading: const Icon(Icons.pending_outlined,
                  color: ShodashaTheme.blue),
              title: Text('Stop ${q.stopId}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '${q.triple['fulls_given'] ?? 0} diye • ${q.triple['empties_back'] ?? 0} wapas • queued ${q.queuedAtIso}'),
            ),
          ),
        for (final r in c.rejected)
          Card(
            shape: ShodashaTheme.shape,
            child: ListTile(
              leading: const Icon(Icons.error_outline,
                  color: ShodashaTheme.danger),
              title: Text('Rejected: ${r['stop_id'] ?? ''}'),
              subtitle: Text('${r['code'] ?? ''} — ${r['message'] ?? ''}'),
            ),
          ),
      ],
    );
  }
}
