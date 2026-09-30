// F3 — Home = booking screen (repeat-machine). Prices unwalled (flow 1-2).
// ui-checklist Card + Adding-to-Cart: name/price/stepper on card, BOOK NOW
// is the single primary action, live deposit feedback, dues/support links.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'booking_controller.dart';
import 'booking_sheet.dart';
import 'stepper.dart';

/// Home/booking screen. Owns no auth: OTP is enforced at booking commit
/// (contract flow 1) by the [onCommitRequiresAuth] gate from F1 wiring.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    this.onCommitRequiresAuth,
  });

  final BookingController controller;

  /// Returns true when the user is authenticated and may proceed.
  /// TODO(F1): wire to AuthController.isAuthenticated + login route.
  final Future<bool> Function()? onCommitRequiresAuth;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _onBookNow() async {
    final c = widget.controller;
    if (!c.canBook) return;
    if (c.isTanker) {
      await showTankerSheet(context);
      return;
    }
    if (c.needsBulkConfirm) {
      final ok = await showBulkConfirmDialog(context, total: c.totalJars);
      if (ok != true) return;
    }
    final gate = widget.onCommitRequiresAuth;
    if (gate != null && !await gate()) return;
    if (!mounted) return;
    await showBookingSheet(context, controller: c);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: ShodashaColors.bg,
      appBar: AppBar(
        backgroundColor: ShodashaColors.bg,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              width: 32,
              height: 32,
              errorBuilder: (ctx, err, stack) => const Icon(
                Icons.water_drop,
                color: ShodashaColors.accent,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Shodasha',
              style: TextStyle(
                color: ShodashaColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          const Text(
            'RO+UV • Lab-tested • Refill Rs 28 / Jar Rs 30',
            style: TextStyle(color: ShodashaColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          // Banner image (local asset; jpg kept, 1.7MB png skipped per spec).
          ClipRRect(
            borderRadius: BorderRadius.circular(kShodashaRadius),
            child: Image.asset(
              'assets/20l.jpg',
              height: 140,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) => Container(
                height: 140,
                color: ShodashaColors.accentSoft,
                alignment: Alignment.center,
                child: const Text(
                  '20L • RO+UV',
                  style: TextStyle(color: ShodashaColors.accent),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SkuCard(
            name: 'Refill (20L)',
            price: 'Rs 28',
            value: c.refillQty,
            onChanged: c.setRefill,
            semantics: 'refill',
          ),
          const SizedBox(height: 12),
          _SkuCard(
            name: 'Jar + Container (20L)',
            price: 'Rs 30',
            value: c.containerQty,
            onChanged: c.setContainer,
            semantics: 'naya jar',
          ),
          const SizedBox(height: 12),
          _EmptiesCard(controller: c),
          const SizedBox(height: 12),
          _DepositStrip(controller: c),
          if (c.holdBlocked || c.duesPaise > 0) ...[
            const SizedBox(height: 12),
            _DuesBanner(controller: c),
          ],
          const SizedBox(height: 12),
          const _HelpRow(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: PressScale(
            onTap: c.canBook ? _onBookNow : null,
            child: Opacity(
              opacity: c.canBook ? 1 : 0.5,
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // Locked spec: BOOK NOW is a black primary.
                  color: ShodashaColors.ink,
                  borderRadius: BorderRadius.circular(kShodashaRadius),
                ),
                child: Text(
                  c.canBook
                      ? 'BOOK NOW • ${rupeesLabel(c.quoteTotalPaise)}'
                      : 'BOOK NOW • kam se kam 1 jar chunein',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkuCard extends StatelessWidget {
  const _SkuCard({
    required this.name,
    required this.price,
    required this.value,
    required this.onChanged,
    required this.semantics,
  });

  final String name;
  final String price;
  final int value;
  final ValueChanged<int> onChanged;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShodashaColors.bg,
        border: Border.all(color: ShodashaColors.border),
        borderRadius: BorderRadius.circular(kShodashaRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ShodashaColors.ink,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  price,
                  style: const TextStyle(
                    color: ShodashaColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          QtyStepper(
            value: value,
            onChanged: onChanged,
            semanticsLabel: semantics,
          ),
        ],
      ),
    );
  }
}

class _EmptiesCard extends StatelessWidget {
  const _EmptiesCard({required this.controller});

  final BookingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShodashaColors.accentSoft,
        border: Border.all(color: ShodashaColors.border),
        borderRadius: BorderRadius.circular(kShodashaRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Khali jar wapas (E)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ShodashaColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rs 150/jar refundable • (N−E)×150 = ${rupeesLabel(controller.depositDuePaise)}',
                  style: const TextStyle(
                    color: ShodashaColors.muted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          QtyStepper(
            value: controller.emptiesQty,
            onChanged: controller.setEmpties,
            semanticsLabel: 'khali jar',
          ),
        ],
      ),
    );
  }
}

class _DepositStrip extends StatelessWidget {
  const _DepositStrip({required this.controller});

  final BookingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: ShodashaColors.border),
        borderRadius: BorderRadius.circular(kShodashaRadius),
      ),
      child: Text(
        'Paani ${rupeesLabel(controller.waterBillPaise)} + Deposit ${rupeesLabel(controller.depositDuePaise)} = Kul ${rupeesLabel(controller.quoteTotalPaise)}',
        style: const TextStyle(color: ShodashaColors.ink, fontSize: 14),
      ),
    );
  }
}

class _DuesBanner extends StatelessWidget {
  const _DuesBanner({required this.controller});

  final BookingController controller;

  @override
  Widget build(BuildContext context) {
    final msg = controller.holdBlocked
        ? '3 se zyada jar hold par — COD band, UPI se order karein'
        : 'Bकaya: ${rupeesLabel(controller.duesPaise)} — bill me jud jayega';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: ShodashaColors.accent),
        borderRadius: BorderRadius.circular(kShodashaRadius),
      ),
      child: Text(msg, style: const TextStyle(color: ShodashaColors.ink)),
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Madad chahiye? WhatsApp karein',
            style: TextStyle(color: ShodashaColors.muted),
          ),
        ),
        TextButton(
          onPressed: () => copySupportNumber(context),
          child: const Text(
            'Help',
            style: TextStyle(color: ShodashaColors.accent),
          ),
        ),
      ],
    );
  }
}

/// N 6–10 bulk confirm dialog (Modal checklist: title/action/close).
Future<bool?> showBulkConfirmDialog(
  BuildContext context, {
  required int total,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kShodashaRadius),
      ),
      title: const Text('6+ jar ka order?'),
      content: Text('$total jar — quantity confirm karein.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Wapas'),
        ),
        PressScale(
          onTap: () => Navigator.of(ctx).pop(true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: ShodashaColors.ink, // black primary (locked spec)
              borderRadius: BorderRadius.circular(kShodashaRadius),
            ),
            child: const Text(
              'Confirm karein',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  );
}

/// WhatsApp guarded fallback: url_launcher is NOT a dep yet (F1 owns
/// pubspec), so copy the number + SnackBar instead of crashing.
/// TODO(F1): open wa.me via url_launcher when the dep lands.
Future<void> copySupportNumber(BuildContext context) async {
  await Clipboard.setData(const ClipboardData(text: kSupportPhone));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('WhatsApp app nahi mila — number copy kiya gaya'),
      ),
    );
  }
}
