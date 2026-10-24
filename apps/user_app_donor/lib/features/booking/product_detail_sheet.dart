// Product detail buy-box (bottom sheet).
//
// Name + photo exactly as the card, variant facts (tap vs no-tap), qty
// stepper, live server deposit/cap facts, ONE primary BUY action, related
// SKU cross-link. No emojis, no gradients, locked tokens, 48dp targets.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'booking_controller.dart';
import 'product_catalog.dart';
import 'stepper.dart';

/// Opens the detail buy-box for [sku]. BUY applies qty to [controller] and
/// calls [onBuy] (caller opens checkout).
Future<void> showProductDetail(
  BuildContext context, {
  required CatalogSku sku,
  required BookingController controller,
  required CatalogRates rates,
  required VoidCallback onBuy,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ShodashaTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ShodashaTheme.radiusSheet),
      ),
    ),
    builder: (_) => _DetailSheet(
      sku: sku,
      controller: controller,
      rates: rates,
      onBuy: onBuy,
    ),
  );
}

class _DetailSheet extends StatefulWidget {
  const _DetailSheet({
    required this.sku,
    required this.controller,
    required this.rates,
    required this.onBuy,
  });

  final CatalogSku sku;
  final BookingController controller;
  final CatalogRates rates;
  final VoidCallback onBuy;

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

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
    final related = skuById(sku.relatedId, widget.rates);
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
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: ShodashaTheme.border,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Stack(
              children: [
                _SheetPhoto(asset: sku.asset),
                Positioned(
                  top: 8,
                  left: 8,
                  child: _SheetIconButton(
                    icon: Icons.close,
                    tooltip: 'Close',
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
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
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
                    fontWeight: FontWeight.w900,
                    color: ShodashaTheme.ink,
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: ShodashaTheme.border),
                borderRadius: BorderRadius.circular(ShodashaTheme.radius),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 18,
                    color: ShodashaTheme.teal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${rupeesLabel(sku.depositPaise)} safety deposit applies '
                      'only to the first container, once • Missing cap: '
                      '${rupeesLabel(sku.capPaise)} • Delivery: morning 8–12, '
                      'daily.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'How many jars?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
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
                rates: widget.rates,
                onBuy: widget.onBuy,
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: ShodashaTheme.border),
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz, color: ShodashaTheme.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Other option: ${related.name} • '
                        '${rupeesLabel(related.pricePaise)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: ShodashaTheme.muted),
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

/// Sheet photo with settle-in entrance (fade + 1.04→1.0 scale, ≤250ms).
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
        cacheWidth: 768,
        errorBuilder: (_, _, _) => Container(
          height: 180,
          color: ShodashaTheme.tealTint,
          alignment: Alignment.center,
          child: const Icon(
            Icons.water_drop,
            size: 48,
            color: ShodashaTheme.teal,
          ),
        ),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return img;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 1.04 - (0.04 * t), child: child),
      ),
      child: img,
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

const TextStyle _body = TextStyle(
  fontSize: 14,
  color: ShodashaTheme.ink,
  height: 1.5,
);
