part of 'stop_detail_screen.dart';

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
          AppButton(
            label: 'Pickup complete karein',
            kind: AppButtonKind.primary,
            icon: Icons.recycling_outlined,
            onPressed: c.submitting
                ? null
                : () => c.completePickup(
                      returnId: widget.returnId,
                      stopId: widget.stopId,
                      emptiesCollected: _empties,
                      capsMissing: _caps,
                    ),
          ),
        ],
      ),
    );
  }
}
