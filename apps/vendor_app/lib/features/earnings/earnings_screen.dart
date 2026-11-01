import 'package:flutter/scheduler.dart';
// Earnings screen: shift summary + flagged-hold note.

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/vendor_locale.dart';
import '../../shared/ui/app_button.dart';
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
    if (!mounted) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
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
      appBar: AppBar(title: Text(vtr('कमाई', 'Earnings'))),
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
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.error ?? 'Load nahi hua',
                  textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Dobara try karein',
                kind: AppButtonKind.primary,
                expand: false,
                onPressed: () => c.load(),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => c.load(),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
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
                    color: ShodashaTheme.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Card 1: Vendor Earned Commission
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
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
                    const Expanded(
                      child: Text(
                        'Aapki Kamai (Commission)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: ShodashaTheme.ink,
                        ),
                      ),
                    ),
                    const Icon(Icons.account_balance_wallet_outlined, color: ShodashaTheme.blue),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  c.earnedPayout > 0
                      ? rupees(c.earnedPayout)
                      : (c.stopsDone > 0 ? 'Settlement Pending' : rupees(0)),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: ShodashaTheme.blue,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  c.stopsDone > 0 && c.earnedPayout == 0
                      ? '${c.stopsDone} stops complete • Hisaab din ke ant me hoga'
                      : '${c.stopsDone} stops complete hue',
                  style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Card 2: Agency Cash Custody (In-Hand Cash)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
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
                    const Expanded(
                      child: Text(
                        'Agency Cash (In-Hand)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: ShodashaTheme.ink,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: ShodashaTheme.amberTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Custody',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ShodashaTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  rupees(c.inHand),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  vtr('ऑर्डर और डिपॉज़िट का कैश एजेंसी या एडमिन को जमा करें।', 'Cash collected from orders & deposit must be submitted to Agency/Admin.'),
                  style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Divider(height: 1, color: ShodashaTheme.border),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text('Cash Collections:', style: TextStyle(fontSize: 12, color: ShodashaTheme.muted)),
                    ),
                    Text(rupees(c.cashTotal), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text('UPI Collections (Direct Bank):', style: TextStyle(fontSize: 12, color: ShodashaTheme.muted)),
                    ),
                    Text(rupees(c.upiTotal), style: const TextStyle(fontWeight: FontWeight.w600, color: ShodashaTheme.blue)),
                  ],
                ),
              ],
            ),
          ),
          if (c.flaggedStops > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
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
                  const SizedBox(height: AppSpacing.xs),
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
            const SizedBox(height: AppSpacing.md),
            Text(c.note!,
                style: const TextStyle(color: ShodashaTheme.muted)),
          ],
        ],
      ),
    );
  }
}
