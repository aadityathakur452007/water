// 005-home-ux — Home storefront (ecommerce, not a text list).
//
// Address bar (default address + change) → app name + search → category
// chips → full-width photo product cards (image left, name/price/stepper
// right, tap = detail buy-box) → sticky book bar with live total.
// ui-checklist Search/Card/Searchbar: top search with placeholder +
// result count, one card style, tappable cards open the detail sheet.
// Locked tokens only: white/black/blue, r8, 48px targets, no emojis.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../addresses/address_screen.dart';
import 'booking_controller.dart';
import 'product_catalog.dart';
import 'product_detail_sheet.dart';
import 'stepper.dart';

/// Home storefront. Owns no auth: OTP is enforced at booking commit
/// (contract flow 1) by [onCommitRequiresAuth]; [onBuy] opens checkout.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    this.onCommitRequiresAuth,
    this.addresses,
    this.onOpenAddresses,
    this.onBuy,
  });

  final BookingController controller;

  /// Returns true when the user is authenticated and may proceed.
  final Future<bool> Function()? onCommitRequiresAuth;

  /// Address source for the delivery bar (null = bar hidden until wired).
  final AddressController? addresses;

  /// Opens the address list/picker (map pin flow).
  final VoidCallback? onOpenAddresses;

  /// Opens checkout for the controller's current lines.
  final VoidCallback? onBuy;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _query = '';
  SkuId? _filter; // null = All
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    widget.addresses?.addListener(_onChange);
    if (widget.addresses?.status == AddrStatus.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.addresses?.load();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    widget.addresses?.removeListener(_onChange);
    _search.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  List<CatalogSku> get _visible {
    var list = searchCatalog(_query);
    if (_filter != null) {
      list = list.where((s) => s.id == _filter).toList();
    }
    return list;
  }

  int _qtyFor(CatalogSku sku) => sku.id == SkuId.refill
      ? widget.controller.refillQty
      : widget.controller.containerQty;

  void _setQty(CatalogSku sku, int v) {
    if (sku.id == SkuId.refill) {
      widget.controller.setRefill(v);
    } else {
      widget.controller.setContainer(v);
    }
  }

  Future<void> _openDetail(CatalogSku sku) async {
    final gate = widget.onCommitRequiresAuth;
    await showProductDetail(
      context,
      sku: sku,
      controller: widget.controller,
      onBuy: () async {
        if (gate != null && !await gate()) return;
        widget.onBuy?.call();
      },
    );
  }

  Future<void> _bookNow() async {
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
    widget.onBuy?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final items = _visible;
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(
        backgroundColor: ShodashaTheme.bg,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              width: 32,
              height: 32,
              errorBuilder: (_, _, _) => const Icon(
                Icons.water_drop,
                color: ShodashaTheme.blue,
              ),
            ),
            const SizedBox(width: 8),
            const Text('Shodasha'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _AddressBar(
            addresses: widget.addresses,
            onChange: widget.onOpenAddresses,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Search: refill, container…',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _Chip(
                  label: 'All',
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: 'Refill',
                  selected: _filter == SkuId.refill,
                  onTap: () => setState(() => _filter = SkuId.refill),
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: 'Containers',
                  selected: _filter == SkuId.container,
                  onTap: () => setState(() => _filter = SkuId.container),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${items.length} products',
            style: const TextStyle(
              fontSize: 13,
              color: ShodashaTheme.muted,
            ),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'Kuch nahi mila — search badal kar dekhein',
                  style: TextStyle(color: ShodashaTheme.muted),
                ),
              ),
            ),
          for (var i = 0; i < items.length; i++) ...[
            _ProductCard(
              sku: items[i],
              qty: _qtyFor(items[i]),
              onQty: (v) => _setQty(items[i], v),
              onOpen: () => _openDetail(items[i]),
            ),
            if (i < items.length - 1) const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ShodashaTheme.blueTint,
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            child: Text(
              'Paani ${rupeesLabel(c.waterBillPaise)} + Deposit '
              '${rupeesLabel(c.depositDuePaise)} = Kul '
              '${rupeesLabel(c.quoteTotalPaise)}',
              style: const TextStyle(
                color: ShodashaTheme.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (c.holdBlocked || c.duesPaise > 0) ...[
            const SizedBox(height: 12),
            _DuesBanner(controller: c),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: c.canBook ? _bookNow : null,
              child: Text(
                c.canBook
                    ? 'BOOK NOW • ${rupeesLabel(c.quoteTotalPaise)}'
                    : 'BOOK NOW • kam se kam 1 jar chunein',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Delivery address bar (default address + change → map-pin flow).
class _AddressBar extends StatelessWidget {
  const _AddressBar({required this.addresses, required this.onChange});

  final AddressController? addresses;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final list = addresses?.items ?? [];
    AddressEntry? current;
    for (final a in list) {
      if (a.isDefault) current = a;
    }
    current ??= list.isEmpty ? null : list.first;
    return PressScale(
      onTap: onChange,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: ShodashaTheme.border),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on, color: ShodashaTheme.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Deliver to',
                    style: TextStyle(
                      fontSize: 12,
                      color: ShodashaTheme.muted,
                    ),
                  ),
                  Text(
                    current == null
                        ? 'Address chunein (map par pin lagayein)'
                        : '${current.label} • ${current.pincode}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Text(
              'Change',
              style: TextStyle(
                color: ShodashaTheme.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? ShodashaTheme.ink : ShodashaTheme.bg,
          border: Border.all(
            color: selected ? ShodashaTheme.ink : ShodashaTheme.border,
          ),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : ShodashaTheme.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Photo product card: image left, name/price/deposit/stepper right.
/// Tap anywhere (except stepper) opens the detail buy-box.
class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.sku,
    required this.qty,
    required this.onQty,
    required this.onOpen,
  });

  final CatalogSku sku;
  final int qty;
  final ValueChanged<int> onQty;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: ShodashaTheme.bg,
          border: Border.all(color: ShodashaTheme.border),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
              child: Image.asset(
                sku.asset,
                width: 112,
                height: 132,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 112,
                  height: 132,
                  color: ShodashaTheme.blueTint,
                  child: const Icon(
                    Icons.water_drop,
                    size: 40,
                    color: ShodashaTheme.blue,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sku.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sku.tagline,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ShodashaTheme.muted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rupeesLabel(sku.pricePaise),
                      style: const TextStyle(
                        color: ShodashaTheme.blue,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    QtyStepper(
                      value: qty,
                      onChanged: onQty,
                      semanticsLabel: sku.name,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
        : 'Bakaya: ${rupeesLabel(controller.duesPaise)} — bill me jud jayega';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: ShodashaTheme.blue),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: ShodashaTheme.blue,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ],
      ),
    );
  }
}

/// N 6–10 bulk confirm dialog (kept from F3: title/action/close).
Future<bool?> showBulkConfirmDialog(
  BuildContext context, {
  required int total,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: ShodashaTheme.shape,
      title: const Text('6+ jar ka order?'),
      content: Text('$total jar — quantity confirm karein.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text(
            'Wapas',
            style: TextStyle(color: ShodashaTheme.muted),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Confirm karein'),
        ),
      ],
    ),
  );
}

/// N > 10 tanker sheet: vendor call CTA only — never creates an order.
Future<void> showTankerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
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
              style: TextStyle(color: ShodashaTheme.muted),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Ho gaya'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
