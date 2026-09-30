// 005-home-ux — Product detail buy-box (bottom sheet).
//
// ui-checklist Cart/Adding-to-Cart: name + image exactly as the card,
// variant facts (tap vs no-tap), qty stepper, delivery-type question
// (Ek baar / Roz / Hafte mein — contract orders vs subscriptions),
// live deposit math, ONE primary BUY action, related-SKU cross-link.
// No emojis, no gradients, locked palette, 48px targets.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'booking_controller.dart';
import 'product_catalog.dart';
import 'stepper.dart';

/// Delivery-type labels (Hindi-first, consistent verbs).
const Map<DeliveryType, String> deliveryTypeLabels = {
  DeliveryType.once: 'Ek baar',
  DeliveryType.daily: 'Roz',
  DeliveryType.alternate: 'Ek din chhodkar',
  DeliveryType.weekly: 'Hafte mein ek baar',
};

/// Opens the detail buy-box for [sku]. BUY applies qty + delivery type to
/// [controller] and calls [onBuy] (caller opens checkout).
Future<void> showProductDetail(
  BuildContext context, {
    required CatalogSku sku,
    required BookingController controller,
    required VoidCallback onBuy,
  }) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (_) => _DetailSheet(sku: sku, controller: controller, onBuy: onBuy),
  );
}

class _DetailSheet extends StatefulWidget {
  const _DetailSheet({
    required this.sku,
    required this.controller,
    required this.onBuy,
  });

  final CatalogSku sku;
  final BookingController controller;
  final VoidCallback onBuy;

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  late int _qty;
  DeliveryType _delivery = DeliveryType.once;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _qty = widget.sku.id == SkuId.refill ? c.refillQty : c.containerQty;
    if (_qty < 1) _qty = 1;
    _delivery = c.deliveryType;
  }

  int get _waterPaise => _qty * widget.sku.pricePaise;

  void _buy() {
    final c = widget.controller;
    if (widget.sku.id == SkuId.refill) {
      c.setRefill(_qty);
      c.setContainer(0);
    } else {
      c.setContainer(_qty);
      c.setRefill(0);
    }
    c.deliveryType = _delivery;
    Navigator.of(context).pop();
    widget.onBuy();
  }

  @override
  Widget build(BuildContext context) {
    final sku = widget.sku;
    final related = skuById(sku.relatedId);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ShodashaTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
              child: Image.asset(
                sku.asset,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: 180,
                  color: ShodashaTheme.blueTint,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.water_drop,
                    size: 48,
                    color: ShodashaTheme.blue,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sku.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: ShodashaTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sku.tagline,
                        style: const TextStyle(
                          fontSize: 13,
                          color: ShodashaTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  rupeesLabel(sku.pricePaise),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(sku.description, style: _body),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ShodashaTheme.blueTint,
                borderRadius: BorderRadius.circular(ShodashaTheme.radius),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: ShodashaTheme.blue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(sku.tapNote, style: _body)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Rs 150/jar refundable deposit sirf naye jar par • '
              'Dhakkan gum par Rs 3 • Delivery subah 8–8 (Ravivar band)',
              style: TextStyle(fontSize: 13, color: ShodashaTheme.muted),
            ),
            const SizedBox(height: 12),
            const Text(
              'Kitne jar?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            QtyStepper(
              value: _qty,
              onChanged: (v) => setState(() => _qty = v < 1 ? 1 : v),
              min: 1,
              semanticsLabel: sku.name,
            ),
            const SizedBox(height: 12),
            const Text(
              'Delivery kaisi ho?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DeliveryType.values.map((t) {
                final selected = t == _delivery;
                return ChoiceChip(
                  label: Text(deliveryTypeLabels[t]!),
                  selected: selected,
                  onSelected: (_) => setState(() => _delivery = t),
                  selectedColor: ShodashaTheme.ink,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : ShodashaTheme.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(ShodashaTheme.radius),
                    side: const BorderSide(color: ShodashaTheme.border),
                  ),
                );
              }).toList(),
            ),
            if (_delivery != DeliveryType.once)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Subscription banega — pause/skip kabhi bhi kar sakte hain.',
                  style: TextStyle(fontSize: 13, color: ShodashaTheme.blue),
                ),
              ),
            const SizedBox(height: 12),
            PressScale(
              onTap: () => showProductDetail(
                context,
                sku: related,
                controller: widget.controller,
                onBuy: widget.onBuy,
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: ShodashaTheme.border),
                  borderRadius:
                      BorderRadius.circular(ShodashaTheme.radius),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.swap_horiz,
                      color: ShodashaTheme.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dusra option: ${related.name} • '
                        '${rupeesLabel(related.pricePaise)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: ShodashaTheme.muted,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _buy,
                child: Text('BUY • ${rupeesLabel(_waterPaise)}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const TextStyle _body =
    TextStyle(fontSize: 14, color: ShodashaTheme.ink, height: 1.5);
