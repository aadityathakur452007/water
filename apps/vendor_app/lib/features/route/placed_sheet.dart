part of 'route_screen.dart';

class _PlacedSheet extends StatefulWidget {
  const _PlacedSheet({required this.controller});

  final RouteController controller;

  @override
  State<_PlacedSheet> createState() => _PlacedSheetState();
}

class _PlacedSheetState extends State<_PlacedSheet> {
  String? _busyId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _accept(Map<String, dynamic> o) async {
    final id = (o['order_id'] ?? '') as String;
    if (id.isEmpty || _busyId != null) return;
    setState(() => _busyId = id);
    final ok = await widget.controller.acceptPlaced(id);
    if (!mounted) return;
    setState(() => _busyId = null);
    // Capture before pop: the sheet context deactivates on close.
    final messenger = ScaffoldMessenger.of(context);
    final notice = widget.controller.acceptNotice;
    if (ok) {
      Navigator.of(context).pop();
    }
    messenger.showSnackBar(
      SnackBar(content: Text(notice ?? 'Ho gaya')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.controller.placed;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Naye orders (${rows.length})',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 4),
            const Text(
              'Accept karte hi stop route me jud jayega',
              style: TextStyle(color: ShodashaTheme.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final o = rows[i];
                  final id = (o['order_id'] ?? '') as String;
                  final label = (o['address_label'] ?? id) as String;
                  final jars = (o['n'] as num?)?.toInt() ?? 0;
                  final total = (o['total'] as num?)?.toInt() ?? 0;
                  final busy = _busyId == id;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('$label • $jars jars',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(rupees(total),
                        style: const TextStyle(color: ShodashaTheme.muted)),
                    trailing: ElevatedButton(
                      onPressed: busy ? null : () => _accept(o),
                      child: Text(busy ? '…' : 'Accept'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
