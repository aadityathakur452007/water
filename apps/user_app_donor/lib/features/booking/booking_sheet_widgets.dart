part of 'booking_sheet.dart';

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShodashaTheme.tealTint,
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ShodashaTheme.teal),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: ShodashaTheme.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.titles});

  final int step;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < titles.length; i++) ...[
          _Dot(index: i, current: step),
          const SizedBox(width: 6),
          Text(
            titles[i],
            style: TextStyle(
              fontWeight: i == step ? FontWeight.w800 : FontWeight.w600,
              color: i <= step ? ShodashaTheme.ink : ShodashaTheme.muted,
              fontSize: i == step ? 14 : 13,
            ),
          ),
          if (i < titles.length - 1) ...[
            const SizedBox(width: 6),
            const Expanded(
              child: Divider(color: ShodashaTheme.border, thickness: 2),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.index, required this.current});

  final int index;
  final int current;

  @override
  Widget build(BuildContext context) {
    final done = index < current;
    final active = index == current;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active || done ? ShodashaTheme.teal : ShodashaTheme.bg,
        border: Border.all(
          color: active || done ? ShodashaTheme.teal : ShodashaTheme.border,
        ),
        shape: BoxShape.circle,
      ),
      child: done
          ? const Icon(Icons.check, size: 14, color: ShodashaTheme.surface)
          : Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? ShodashaTheme.surface : ShodashaTheme.muted,
              ),
            ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.address, required this.onChange});

  final AddressEntry? address;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final a = address;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: ShodashaTheme.tealTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on,
              color: ShodashaTheme.teal,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: a == null
                ? const Text('Choose a delivery address')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${a.label} • ${a.pincode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        addressDetailLine(a),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: ShodashaTheme.muted,
                        ),
                      ),
                    ],
                  ),
          ),
          TextButton(
            onPressed: onChange,
            child: Text(a == null ? 'Add address' : 'Change'),
          ),
        ],
      ),
    );
  }
}

class _PayChip extends StatelessWidget {
  const _PayChip({
    required this.label,
    required this.selected,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      constraints: const BoxConstraints(minHeight: ShodashaTheme.minTarget),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? ShodashaTheme.teal : ShodashaTheme.surface,
        border: Border.all(
          color: selected ? ShodashaTheme.teal : ShodashaTheme.border,
        ),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? ShodashaTheme.surface : ShodashaTheme.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (!enabled || onTap == null) {
      return Opacity(
        opacity: 0.5,
        child: Semantics(
          button: true,
          enabled: false,
          label: '$label — unavailable',
          child: ExcludeSemantics(child: box),
        ),
      );
    }
    return Semantics(
      button: true,
      enabled: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(onTap: onTap, child: box),
      ),
    );
  }
}
