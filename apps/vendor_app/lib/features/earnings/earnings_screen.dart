// Earnings screen: shift summary + flagged-hold note.

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import 'earnings_controller.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key, required this.controller});

  final EarningsController controller;

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
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
      appBar: AppBar(title: const Text('Earnings / कमाई')),
      body: _body(c),
    );
  }

  Widget _body(EarningsController c) {
    if (c.state == EarningsState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (c.state == EarningsState.error ||
        c.state == EarningsState.offline) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.error ?? 'Load nahi hua',
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
    return RefreshIndicator(
      onRefresh: () => c.load(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section-header row: label left, live stop count right.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Aaj ki kamai',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              Text(
                '${c.stopsDone} stops',
                style: const TextStyle(
                    color: ShodashaTheme.muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: ShodashaTheme.border),
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c.stopsDone} stops done',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('Cash: ${rupees(c.cashTotal)}'),
                Text('UPI: ${rupees(c.upiTotal)}'),
                Text(
                  'Total: ${rupees(c.cashTotal + c.upiTotal)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (c.flaggedStops > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: ShodashaTheme.border),
                borderRadius:
                    BorderRadius.circular(ShodashaTheme.radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.flaggedHold > 0
                        ? '${c.flaggedStops} stops review me — ${rupees(c.flaggedHold)} hold par'
                        : '${c.flaggedStops} stops review me',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: ShodashaTheme.danger),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sirf jankari — payout admin clear ke baad, yahan se action nahi.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ShodashaTheme.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
          if (c.note != null) ...[
            const SizedBox(height: 12),
            Text(c.note!,
                style: const TextStyle(color: ShodashaTheme.muted)),
          ],
        ],
      ),
    );
  }
}
