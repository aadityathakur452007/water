// F3 — Booking sheet: quote lock + window + pay mode + confirm.
// Gates: idempotency once per sheet-open (retry reuse), silent re-quote
// pre-confirm (>15min or changed), COD disabled over cap/held/dues,
// window default = kal subah ex-Sun/holiday (contract §§4.2/4.4).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'booking_controller.dart';
import 'quote_confirm.dart';
import 'stepper.dart';

/// Opens the booking bottom sheet. Mints the idempotency key once here.
Future<void> showBookingSheet(
  BuildContext context, {
  required BookingController controller,
}) {
  controller.ensureIdempotencyKey();
  controller.windowDay ??= nextServiceableDay(DateTime.now());
  controller.freezeQuote(DateTime.now().toUtc());
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(kShodashaRadius),
      ),
    ),
    builder: (_) => BookingSheet(controller: controller),
  );
}

/// N > 10 tanker sheet: vendor call CTA only — never creates an order
/// (contract EC-O03). tel: guarded with a copy fallback.
Future<void> showTankerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(kShodashaRadius),
      ),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tanker supply',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              '10 se zyada jar ke liye tanker lagta hai. Vendor se baat karein.',
              style: TextStyle(color: ShodashaColors.muted),
            ),
            const SizedBox(height: 16),
            // TODO(F1): dial via url_launcher tel: when the dep lands.
            PressScale(
              onTap: () async {
                await Clipboard.setData(
                  const ClipboardData(text: kVendorPhone),
                );
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Vendor number copy kiya gaya'),
                    ),
                  );
                }
              },
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ShodashaColors.ink, // black primary (locked spec)
                  borderRadius: BorderRadius.circular(kShodashaRadius),
                ),
                child: const Text(
                  'Vendor ko call karein',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class BookingSheet extends StatefulWidget {
  const BookingSheet({super.key, required this.controller});

  final BookingController controller;

  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  bool _requoted = false;

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

  void _confirm() {
    final c = widget.controller;
    // Silent re-quote pre-confirm: >15min or inputs changed since freeze.
    final didRequote = c.silentRequoteIfNeeded(DateTime.now().toUtc());
    if (c.paymentMode == PaymentMode.cod && !c.codAllowed) return;
    setState(() => _requoted = didRequote);
    // TODO(F1): POST /quotes then POST /orders with Idempotency-Key header
    // (controller.ensureIdempotencyKey, reused on retry) + quote_hash.
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    // Freeze values before closing (controller is live).
    final total = c.quoteTotalPaise;
    final key = c.ensureIdempotencyKey();
    nav.pop();
    unawaitedShowConfirm(context, totalPaise: total, idempotencyKey: key);
    if (didRequote && mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Daam update hua — naya quote lagaya')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final codOk = c.codAllowed;
    final day = c.windowDay ?? nextServiceableDay(DateTime.now());
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quote lock',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 8),
            _QuoteLines(controller: c),
            if (_requoted)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Daam update hua — naya quote lagaya gaya',
                  style: TextStyle(
                    color: ShodashaColors.accent,
                    fontSize: 13,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Window: kal subah • ${_fmtDay(day)} (8–8, Sun band)',
              style: const TextStyle(color: ShodashaColors.muted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _PayChip(
                  label: 'UPI',
                  selected: c.paymentMode == PaymentMode.upi,
                  onTap: () => setState(
                    () => c.paymentMode = PaymentMode.upi,
                  ),
                ),
                const SizedBox(width: 8),
                _PayChip(
                  label: 'COD (cash)',
                  selected: c.paymentMode == PaymentMode.cod,
                  enabled: codOk,
                  onTap: codOk
                      ? () => setState(
                            () => c.paymentMode = PaymentMode.cod,
                          )
                      : null,
                ),
              ],
            ),
            if (!codOk)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  c.holdBlocked
                      ? '3 se zyada jar hold par — COD band, UPI chunein'
                      : 'Rs 2,000 se zyada / bकaya par COD nahi — UPI chunein',
                  style: const TextStyle(
                    color: ShodashaColors.muted,
                    fontSize: 13,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            PressScale(
              onTap: (c.paymentMode == PaymentMode.cod && !codOk)
                  ? null
                  : _confirm,
              child: Opacity(
                opacity: (c.paymentMode == PaymentMode.cod && !codOk)
                    ? 0.5
                    : 1,
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ShodashaColors.ink, // black primary (locked spec)
                    borderRadius: BorderRadius.circular(kShodashaRadius),
                  ),
                  child: Text(
                    'Confirm • ${rupeesLabel(c.quoteTotalPaise)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtDay(DateTime d) => '${d.day}/${d.month}/${d.year}';

class _QuoteLines extends StatelessWidget {
  const _QuoteLines({required this.controller});

  final BookingController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: ShodashaColors.border),
        borderRadius: BorderRadius.circular(kShodashaRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Paani: ${rupeesLabel(c.waterBillPaise)}'),
          Text(
            'Deposit (N−E)×150: ${rupeesLabel(c.depositDuePaise)}',
          ),
          if (c.capsMissing > 0)
            Text('Cap missing ×${c.capsMissing}: '
                '${rupeesLabel(c.capsMissing * kCapChargePaise)}'),
          const Divider(),
          Text(
            'Kul: ${rupeesLabel(c.quoteTotalPaise)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
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
    final Widget box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? ShodashaColors.accent : ShodashaColors.bg,
        border: Border.all(
          color: selected ? ShodashaColors.accent : ShodashaColors.border,
        ),
        borderRadius: BorderRadius.circular(kShodashaRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : ShodashaColors.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (!enabled) return Opacity(opacity: 0.5, child: box);
    return PressScale(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.5,
        child: box,
      ),
    );
  }
}
