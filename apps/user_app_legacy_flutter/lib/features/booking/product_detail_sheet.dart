// 005-home-ux — Product detail buy-box (bottom sheet).
//
// ui-checklist Cart/Adding-to-Cart: name + image exactly as the card,
// variant facts (tap vs no-tap), qty stepper, delivery-type question
// (Ek baar / Roz / Hafte mein — contract orders vs subscriptions),
// live deposit math, ONE primary BUY action, related-SKU cross-link.
// No emojis, no gradients, locked palette, 48px targets.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

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
  DeliveryType.custom: 'Tareekhein chunein',
};

/// Icons for the delivery-type chips (no emojis — Material icons only).
const Map<DeliveryType, IconData> deliveryTypeIcons = {
  DeliveryType.once: Icons.bolt_outlined,
  DeliveryType.daily: Icons.repeat,
  DeliveryType.alternate: Icons.calendar_view_week_outlined,
  DeliveryType.weekly: Icons.date_range_outlined,
  DeliveryType.custom: Icons.edit_calendar_outlined,
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

// 014: qty-only buy-box — schedule lives on home cards + checkout.
// No second delivery picker here (was duplicating booking_sheet chips).
class _DetailSheetState extends State<_DetailSheet> {
  late int _qty;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _qty = widget.sku.id == SkuId.refill ? c.refillQty : c.containerQty;
    if (_qty < 1) _qty = 1;
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
            Stack(
              children: [
                _SheetPhoto(asset: sku.asset),
                // Icon-over-photo rhythm (reference hero stack): back/close
                // top-left over the photo zone. No search icon — a dead
                // control would be a fake affordance.
                Positioned(
                  top: 8,
                  left: 8,
                  child: _SheetIconButton(
                    icon: Icons.close,
                    tooltip: 'Band karein',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
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
            // Bordered fact row (reference CustomCard shape): deposit / cap /
            // hours facts with icon lead. Tap-note keeps the blueTint callout.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: ShodashaTheme.border),
                borderRadius:
                    BorderRadius.circular(ShodashaTheme.radius),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 18,
                    color: ShodashaTheme.blue,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rs 150 safety deposit sirf pehle container par, ek baar • '
                      'Dhakkan gum par Rs 3 • Delivery Subah 8–12, har din',
                      style:
                          TextStyle(fontSize: 13, color: ShodashaTheme.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Title ↔ stepper on one row (reference title-row rhythm) —
            // compresses the vertical stack, targets stay 48dp.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Kitne jar?',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                QtyStepper(
                  value: _qty,
                  onChanged: (v) => setState(() => _qty = v < 1 ? 1 : v),
                  min: 1,
                  semanticsLabel: sku.name,
                ),
              ],
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

/// Sheet photo with settle-in entrance (fade + 1.04→1.0 scale, ≤250ms,
/// easeOut — the reference 800ms scale is cut per the motion rule).
/// Static render when the OS asks for reduced motion.
class _SheetPhoto extends StatelessWidget {
  const _SheetPhoto({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    final img = ClipRRect(
      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      child: Image.asset(
        asset,
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
        // P4: decode near display size (card is ~2x of 112px home art).
        cacheWidth: 768,
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
    );
    if (MediaQuery.disableAnimationsOf(context)) return img;
    return img
        .animate()
        .fade(duration: 200.ms)
        .scale(
          begin: const Offset(1.04, 1.04),
          end: const Offset(1, 1),
          duration: 250.ms,
          curve: Curves.easeOut,
        );
  }
}

/// 48dp circular icon button for photo overlays (white + hairline border).
class _SheetIconButton extends StatelessWidget {
  const _SheetIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: ShodashaTheme.minTarget,
          height: ShodashaTheme.minTarget,
          decoration: BoxDecoration(
            color: ShodashaTheme.bg,
            shape: BoxShape.circle,
            border: Border.all(color: ShodashaTheme.border),
          ),
          child: Icon(icon, color: ShodashaTheme.ink),
        ),
      ),
    );
  }
}

const TextStyle _body =
    TextStyle(fontSize: 14, color: ShodashaTheme.ink, height: 1.5);
