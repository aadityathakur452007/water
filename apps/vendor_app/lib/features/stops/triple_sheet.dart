// Triple sheet: one-hand 48dp steppers for fulls/empties/caps + cash/UPI
// split. Cash/UPI are whole-Rs inputs converted to paise (no float math).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../sync/sync_controller.dart';
import 'stops_controller.dart';

class TripleSheet extends StatefulWidget {
  const TripleSheet({
    super.key,
    required this.controller,
    required this.stopId,
    required this.fullsExp,
    required this.emptiesExp,
    this.outbox,
    this.collectPaise = 0,
    this.paymentMode = 'cod',
  });

  final StopsController controller;
  final String stopId;
  final int fullsExp;
  final int emptiesExp;
  final SyncController? outbox;

  /// 015: collect hint from the joined stop (total + mode).
  final int collectPaise;
  final String paymentMode;

  @override
  State<TripleSheet> createState() => _TripleSheetState();
}

class _TripleSheetState extends State<TripleSheet> {
  int _fulls = 0;
  int _empties = 0;
  int _caps = 0;
  final _cash = TextEditingController(text: '0');
  final _upi = TextEditingController(text: '0');

  @override
  void dispose() {
    _cash.dispose();
    _upi.dispose();
    super.dispose();
  }

  int _rs(TextEditingController t) => int.tryParse(t.text.trim()) ?? 0;

  Widget _stepper(String label, int value, ValueChanged<int> set) {
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          iconSize: 32,
          constraints:
              const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: value > 0 ? () => set(value - 1) : null,
        ),
        SizedBox(
          width: 40,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline,
              color: ShodashaTheme.blue),
          iconSize: 32,
          constraints:
              const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => set(value + 1),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final capRs = capChargeRs(_caps);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Triple / तीन काम एक साथ',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('Expected: ${widget.fullsExp} diye • ${widget.emptiesExp} wapas',
                style: const TextStyle(color: ShodashaTheme.muted)),
            if (widget.collectPaise > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${widget.paymentMode.toUpperCase()} • Collect ${rupees(widget.collectPaise)}',
                  style: const TextStyle(
                      color: ShodashaTheme.blue, fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(height: 12),
            _stepper('Jars diye', _fulls, (v) => setState(() => _fulls = v)),
            _stepper('Khaali wapas', _empties,
                (v) => setState(() => _empties = v)),
            _stepper('Bina dhakkan ($_caps × Rs 3 = Rs $capRs)', _caps,
                (v) => setState(() => _caps = v)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cash,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Cash liya (Rs)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _upi,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration:
                        const InputDecoration(labelText: 'UPI liya (Rs)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: c.submitting
                  ? null
                  : () async {
                      late final Map<String, dynamic> body;
                      try {
                        body = buildTripleBody(
                          fullsGiven: _fulls,
                          emptiesBack: _empties,
                          cashPaise: _rs(_cash) * 100,
                          upiPaise: _rs(_upi) * 100,
                          capsMissing: _caps,
                          version: c.version,
                        );
                      } on ArgumentError catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$e')));
                        return;
                      }
                      final ok = await c.commitTriple(
                        stopId: widget.stopId,
                        triple: body,
                      );
                      // Offline: queue with the same idempotency key shape the
                      // sync worker replays (server dedupes on retry).
                      if (!ok &&
                          (c.notice ?? '').contains('Sync me queue') &&
                          widget.outbox != null) {
                        await widget.outbox!.enqueue(
                          stopId: widget.stopId,
                          triple: body,
                        );
                      }
                      if (context.mounted && ok) Navigator.of(context).pop();
                      if (context.mounted && !ok && c.notice != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(c.notice!)));
                      }
                    },
              child: Text(c.submitting
                  ? 'Save ho raha…'
                  : 'Confirm triple / पक्का करें'),
            ),
          ],
        ),
      ),
    );
  }
}
