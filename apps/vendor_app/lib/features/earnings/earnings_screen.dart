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
          // Card 1: Vendor Earned Commission
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: ShodashaTheme.blueTint,
              border: Border.all(color: ShodashaTheme.blue),
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Aapki Kamai (Commission)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                    const Icon(Icons.account_balance_wallet_outlined, color: ShodashaTheme.blue),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  c.earnedPayout > 0 ? rupees(c.earnedPayout) : rupees(c.stopsDone * 2000), // default Rs 20/stop
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: ShodashaTheme.blue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${c.stopsDone} stops complete hue',
                  style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Card 2: Agency Cash Custody (In-Hand Cash)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: ShodashaTheme.bg,
              border: Border.all(color: ShodashaTheme.border),
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Agency Cash (In-Hand)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Custody',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  rupees(c.inHand),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Orders aur deposit se liya gaya cash — Agency / Admin ko jama karein.',
                  style: TextStyle(fontSize: 12, color: ShodashaTheme.muted),
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: ShodashaTheme.border),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Cash Collections:', style: const TextStyle(fontSize: 13, color: ShodashaTheme.muted)),
                    Text(rupees(c.cashTotal), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('UPI Collections (Direct Bank):', style: const TextStyle(fontSize: 13, color: ShodashaTheme.muted)),
                    Text(rupees(c.upiTotal), style: const TextStyle(fontWeight: FontWeight.w600, color: ShodashaTheme.blue)),
                  ],
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
