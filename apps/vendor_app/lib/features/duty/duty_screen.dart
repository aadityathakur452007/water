// Duty screen: big on/off switch + capacity/custody meters.

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import 'duty_controller.dart';

class DutyScreen extends StatefulWidget {
  const DutyScreen({super.key, required this.controller});

  final DutyController controller;

  @override
  State<DutyScreen> createState() => _DutyScreenState();
}

class _DutyScreenState extends State<DutyScreen> {
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
      appBar: AppBar(title: const Text('Duty / ड्यूटी')),
      body: _body(c),
    );
  }

  Widget _body(DutyController c) {
    if (c.state == DutyState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (c.state == DutyState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: ShodashaTheme.danger),
              const SizedBox(height: 12),
              Text(c.error ?? 'Kuch galat hua',
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
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: ShodashaTheme.shape,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.onDuty ? 'On duty / ड्यूटी पर' : 'Off duty / छुट्टी',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Switch(
                      value: c.onDuty,
                      activeTrackColor: ShodashaTheme.blue,
                      // S16: going off-duty mid-route is destructive — confirm.
                      onChanged: (v) async {
                        if (!v && c.onDuty) {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: ShodashaTheme.shape,
                              title: const Text('Duty off karein?'),
                              content: const Text(
                                  'Baki stops aaj ke liye ruk jayenge. Pakka off karna hai?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(false),
                                  child: const Text('Rehne dein'),
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(true),
                                  child: const Text('Haan, off karein'),
                                ),
                              ],
                            ),
                          );
                          if (ok != true || !context.mounted) return;
                        }
                        await c.setDuty(v);
                      },
                    ),
                  ],
                ),
                if (c.since != null)
                  Text('Since: ${c.since}',
                      style:
                          const TextStyle(color: ShodashaTheme.muted)),
                // Phase 5 §5.3: repool honesty after duty-off.
                if (!c.onDuty && c.lastRepooled > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${c.lastRepooled} stops wapas pool mein — dispatch dobara assign karega',
                      style: const TextStyle(
                          color: ShodashaTheme.muted,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                    'Stops: ${c.stopsToday}/${c.maxStops} • Jars: ${c.jarsAllocated}/${c.maxJars}'),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: c.maxStops == 0
                      ? 0
                      : (c.stopsToday / c.maxStops).clamp(0.0, 1.0),
                  backgroundColor: ShodashaTheme.border,
                  color: ShodashaTheme.blue,
                ),
                const SizedBox(height: 16),
                Text('Haath me: ${rupees(c.cashInHand)} / in hand'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
