// 005-home-ux — Home storefront (ecommerce, not a text list).
//
// Address bar (default address + change) → app name + search → category
// chips → full-width photo product cards (image left, name/price/stepper
// right, tap = detail buy-box) → sticky book bar with live total.
// ui-checklist Search/Card/Searchbar: top search with placeholder +
// result count, one card style, tappable cards open the detail sheet.
// Locked tokens only: white/black/blue, r8, 48px targets, no emojis.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_client.dart' show kSupportPhone;
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
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  // Search killed per 014 approval (2 SKUs need no search/filter).
  List<CatalogSku> get _visible => kCatalog;

  /// Staggered card entrance — transform + opacity only; static render
  /// when the OS asks for reduced motion.
  Widget _entrance(Widget child, int index) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return child
        .animate(delay: Duration(milliseconds: 60 * index))
        .fade(duration: 200.ms)
        .slideY(
          begin: 0.15,
          end: 0,
          duration: 200.ms,
          curve: Curves.easeOut,
        );
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
              // 32px display size: decode at display resolution only
              // (Phase 4 §4.6; full WebP re-export is an owner asset step).
              cacheWidth: 32,
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
          const _GreetingHeader(),
          const SizedBox(height: 12),
          _AddressBar(
            addresses: widget.addresses,
            onChange: widget.onOpenAddresses,
          ),
          const SizedBox(height: 12),
          // 014: Choose Your Schedule (HYDROFAST layout, our tokens).
          // Two cards only — one-tap, no slot-times, fixed Subah 8–12 promise.
          _ScheduleCards(controller: c),
          const SizedBox(height: 12),
          // 014: wallet-safe strip — deposit trust earned by showing it.
          _WalletStrip(addresses: widget.addresses),
          const SizedBox(height: 4),
          const Text('Sab products',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ShodashaTheme.ink)),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 200,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _entrance(
              _GridCard(
                sku: items[i],
                onOpen: () => _openDetail(items[i]),
              ),
              i,
            ),
          ),
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
    final current = addresses?.resolve();
    return ListTile(
      leading: const Icon(Icons.location_on, color: ShodashaTheme.blue),
      title: const Text(
        'Deliver to',
        style: TextStyle(fontSize: 12, color: ShodashaTheme.muted),
      ),
      subtitle: Text(
        current == null
            ? 'Address chunein (map par pin lagayein)'
            : '${current.label} • ${current.pincode}',
        style: const TextStyle(fontWeight: FontWeight.w700),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: TextButton(
        onPressed: onChange,
        child: const Text(
          'Change',
          style: TextStyle(
            color: ShodashaTheme.blue,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      onTap: onChange,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
    );
  }
}



/// 014: Two schedule cards (HYDROFAST layout, Shodasha tokens).
/// Ek Baar = once, fixed Subah 8–12. Roz ka Plan = daily subscription.
/// No slot-times, no calendar — one tap sets controller.deliveryType.
class _ScheduleCards extends StatelessWidget {
  const _ScheduleCards({required this.controller});
  final BookingController controller;

  @override
  Widget build(BuildContext context) {
    final isOnce = controller.deliveryType == DeliveryType.once;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ORDER WATER',
            style: TextStyle(fontSize: 11, color: ShodashaTheme.muted, fontWeight: FontWeight.w700)),
        const Text('Choose Your Schedule',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ShodashaTheme.ink)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ScheduleCard(
                title: 'Ek Baar',
                sub: 'Subah 8–12',
                icon: Icons.bolt_outlined,
                selected: isOnce,
                onTap: () => controller.deliveryType = DeliveryType.once,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ScheduleCard(
                title: 'Roz ka Plan',
                sub: 'Auto-refill',
                icon: Icons.repeat,
                selected: !isOnce,
                onTap: () => controller.deliveryType = DeliveryType.daily,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text('Har din paani — Subah 8–12 fixed window',
            style: TextStyle(fontSize: 12, color: ShodashaTheme.muted)),
      ],
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard(
      {required this.title, required this.sub, required this.icon, required this.selected, required this.onTap});
  final String title;
  final String sub;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? ShodashaTheme.blueTint : ShodashaTheme.bg,
          border: Border.all(
              color: selected ? ShodashaTheme.blue : ShodashaTheme.border),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: ShodashaTheme.blue),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(sub, style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted)),
          ],
        ),
      ),
    );
  }
}

/// 014: wallet-safe strip — shows held deposit so trust is earned by
/// visibility, not a badge. Data comes from ledger when wired; until then
/// honest fallback copy (no invented balances).
class _WalletStrip extends StatelessWidget {
  const _WalletStrip({required this.addresses});
  final AddressController? addresses;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, size: 18, color: ShodashaTheme.blue),
          SizedBox(width: 8),
          Expanded(
              child: Text('Safety deposit app me safe hai — Profile me dekhein',
                  style: TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

/// Greeting header rhythm (layout echo of the reference ListTile header:
/// small overline + bold title + round leading mark) — our tokens, Hindi
/// copy, icon mark instead of an avatar photo (no invented imagery).
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: ShodashaTheme.minTarget,
          height: ShodashaTheme.minTarget,
          decoration: const BoxDecoration(
            color: ShodashaTheme.blueTint,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.water_drop,
            color: ShodashaTheme.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: const TextStyle(
                  fontSize: 12,
                  color: ShodashaTheme.muted,
                ),
              ),
              const Text(
                'Paani book karein',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ShodashaTheme.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Time-aware greeting — pure widget copy, no backend, no session.
String _greeting() {
  final h = DateTime.now().hour;
  if (h >= 5 && h < 12) return 'Shubh prabhat';
  if (h >= 17 && h < 22) return 'Shubh sandhya';
  return 'Namaste';
}

/// Slim photo grid card: photo + name + price + corner add-button.
/// Qty lives in the detail buy-box — tapping the card OR the + opens it
/// (the + is a visual affordance; the whole card is the 48dp+ tap target,
/// so there is no nested-gesture double-open).
class _GridCard extends StatelessWidget {
  const _GridCard({
    required this.sku,
    required this.onOpen,
  });

  final CatalogSku sku;
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
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                  child: Image.asset(
                    sku.asset,
                    height: 120,
                    fit: BoxFit.cover,
                    // P4: decode at ~2x display size, never full-res.
                    cacheWidth: 448,
                    errorBuilder: (_, _, _) => Container(
                      height: 120,
                      color: ShodashaTheme.blueTint,
                      child: const Icon(
                        Icons.water_drop,
                        size: 40,
                        color: ShodashaTheme.blue,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 64, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sku.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: ShodashaTheme.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rupeesLabel(sku.pricePaise),
                        style: const TextStyle(
                          color: ShodashaTheme.blue,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                width: ShodashaTheme.minTarget,
                height: ShodashaTheme.minTarget,
                decoration: const BoxDecoration(
                  color: ShodashaTheme.ink,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add,
                  color: ShodashaTheme.bg,
                  semanticLabel: 'Detail kholein',
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

/// N > 10 tanker sheet: vendor call CTA + dismiss — never creates an order.
/// Phase 4 §4.5: the Call button dials the real support number (single
/// [kSupportPhone] constant); [openUrl] is the widget-test seam.
Future<void> showTankerSheet(
  BuildContext context, {
  Future<bool> Function(Uri url, {LaunchMode mode})? openUrl,
}) {
  Future<void> callVendor(BuildContext ctx) async {
    final digits = kSupportPhone.replaceAll(RegExp(r'\D'), '');
    final open = openUrl ?? launchUrl;
    bool ok = false;
    try {
      ok = await open(Uri(scheme: 'tel', path: '+$digits'));
    } catch (_) {
      ok = false;
    }
    if (ok || !ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text('Call nahi laga — $kSupportPhone par call karein')),
    );
  }

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
                onPressed: () => callVendor(ctx),
                child: const Text('Vendor ko call karein'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
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
