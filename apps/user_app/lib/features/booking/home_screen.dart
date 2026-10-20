// Home storefront (S3): address bar, schedule cards, server-priced product
// grid, live estimate strip, and the money CTA.
//
// Money law: prices come from GET /catalog through [BookingController.rates].
// There are no fallback rates. While prices load we show an honest loading
// state; on failure we show the error + retry. The BOOK NOW amount is the
// server-priced estimate, never a client-invented number.
//
// Standalone by design: the shell passes its own controller/api/address
// source and callbacks; [HomeScreen] owns no auth or navigation policy.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/payment_config.dart';
import '../../core/theme.dart';
import '../addresses/address_screen.dart';
import 'booking_controller.dart';
import 'booking_sheet.dart';
import 'product_catalog.dart';
import 'product_detail_sheet.dart';
import 'quote_confirm.dart';
import 'stepper.dart';

/// Home tab. Owns no auth: [ensureAuth] gates money actions at BUY/BOOK NOW.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    this.api,
    this.addresses,
    this.ensureAuth,
    this.onOpenAddresses,
    this.onBuy,
    this.onTrackOrder,
    this.onOpenSubscriptions,
    this.razorpayKeyId = kRazorpayKeyId,
  });

  final BookingController controller;

  /// Live API. When present (and the controller has no catalog yet), Home
  /// attaches [HttpCatalogApi] and fetches the server rate snapshot.
  final ApiClient? api;

  /// Delivery address source (null = the address bar asks the user to add).
  final AddressController? addresses;

  /// Returns true when the user may proceed with a money action.
  final Future<bool> Function()? ensureAuth;

  /// Opens the address list/picker.
  final VoidCallback? onOpenAddresses;

  /// Opens checkout for the current lines. When null and [api] is present,
  /// Home opens the checkout sheet itself.
  final VoidCallback? onBuy;

  final VoidCallback? onTrackOrder;
  final VoidCallback? onOpenSubscriptions;
  final String razorpayKeyId;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    widget.addresses?.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final api = widget.api;
      if (api != null) {
        widget.controller.ensureCatalog(HttpCatalogApi(api));
        if (!widget.controller.hasRates) {
          widget.controller.refreshRates();
        }
      }
      if (widget.addresses?.status == AddrStatus.initial) {
        widget.addresses?.load();
      }
    });
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

  Future<bool> _gate() async {
    final gate = widget.ensureAuth;
    if (gate == null) return true;
    return gate();
  }

  Future<void> _openDetail(CatalogSku sku) async {
    final rates = widget.controller.rates;
    if (rates == null) return;
    await showProductDetail(
      context,
      sku: sku,
      controller: widget.controller,
      rates: rates,
      onBuy: () async {
        if (!await _gate()) return;
        if (!mounted) return;
        _buy();
      },
    );
  }

  Future<void> _bookNow() async {
    final c = widget.controller;
    if (!c.canBook || c.rates == null) return;
    if (c.isTanker) {
      await showTankerSheet(context);
      return;
    }
    if (c.needsBulkConfirm) {
      final ok = await showBulkConfirmDialog(context, total: c.totalJars);
      if (ok != true) return;
    }
    if (!await _gate()) return;
    if (!mounted) return;
    _buy();
  }

  void _buy() {
    final external = widget.onBuy;
    if (external != null) {
      external();
      return;
    }
    final api = widget.api;
    if (api == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checkout is unavailable right now.')),
      );
      return;
    }
    final c = widget.controller;
    showCheckoutSheet(
      context,
      controller: c,
      api: api,
      razorpayKeyId: widget.razorpayKeyId,
      address: widget.addresses?.resolve(),
      onChangeAddress: () {
        Navigator.of(context).pop();
        widget.onOpenAddresses?.call();
      },
      onDone: (result) {
        Navigator.of(context).pop();
        showOrderConfirm(
          context,
          result: result,
          onTrackOrder: widget.onTrackOrder,
          onOpenSubscriptions: widget.onOpenSubscriptions,
        );
      },
    );
  }

  Widget _entrance(Widget child, int index) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return child
        .animate(delay: Duration(milliseconds: 60 * index))
        .fade(duration: 200.ms)
        .slideY(begin: 0.15, end: 0, duration: 200.ms, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final rates = c.rates;
    final items = rates == null ? const <CatalogSku>[] : catalogFor(rates);
    final canBook = c.canBook && rates != null && !c.ratesLoading;
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const _BrandHeader(),
          const SizedBox(height: 12),
          _AddressBar(
            addresses: widget.addresses,
            onChange: widget.onOpenAddresses,
          ),
          const SizedBox(height: 16),
          const _GreetingHeader(),
          const SizedBox(height: 14),
          _ScheduleCards(controller: c),
          const SizedBox(height: 12),
          const _WalletStrip(),
          const SizedBox(height: 16),
          const Text(
            'ALL PRODUCTS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: ShodashaTheme.muted,
            ),
          ),
          const SizedBox(height: 8),
          if (rates == null)
            _RatesPanel(controller: c)
          else ...[
            if (c.ratesError != null) ...[
              _StaleRatesBanner(controller: c),
              const SizedBox(height: 8),
            ],
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 226,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => _entrance(
                _GridCard(sku: items[i], onOpen: () => _openDetail(items[i])),
                i,
              ),
            ),
            const SizedBox(height: 12),
            _EstimateStrip(controller: c),
          ],
          if (c.holdBlocked || c.duesPaise > 0) ...[
            const SizedBox(height: 12),
            _DuesBanner(controller: c),
          ],
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: ShodashaTheme.surface,
          border: Border(top: BorderSide(color: ShodashaTheme.border)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: canBook ? _bookNow : null,
              child: Text(
                canBook
                    ? 'BOOK NOW • ${rupeesLabel(c.quoteTotalPaise!)}'
                    : rates == null
                        ? 'BOOK NOW • Prices unavailable'
                        : 'BOOK NOW • Choose at least 1 jar',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Teal brand header (donor grammar): logo + wordmark + support line.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(
        color: ShodashaTheme.teal,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(ShodashaTheme.radiusLg),
        ),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/logo.png',
            width: 34,
            height: 34,
            cacheWidth: 68,
            errorBuilder: (_, _, _) => const Icon(
              Icons.water_drop,
              color: ShodashaTheme.surface,
              size: 30,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SHODASHA',
                  style: TextStyle(
                    color: ShodashaTheme.surface,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'Clean water, delivered every morning',
                  style: TextStyle(
                    color: ShodashaTheme.tealTint,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressBar extends StatelessWidget {
  const _AddressBar({required this.addresses, required this.onChange});

  final AddressController? addresses;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final current = addresses?.resolve();
    return Material(
      color: ShodashaTheme.surface,
      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      child: InkWell(
        onTap: onChange,
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            border: Border.all(color: ShodashaTheme.border),
            borderRadius: BorderRadius.circular(ShodashaTheme.radius),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: ShodashaTheme.tealTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  color: ShodashaTheme.teal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DELIVER TO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: ShodashaTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      current == null
                          ? 'Choose a delivery address'
                          : '${current.label} • ${current.pincode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                    if (current != null)
                      Text(
                        addressDetailLine(current),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: ShodashaTheme.muted,
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onChange,
                child: Text(current == null ? 'Add' : 'Change'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
            color: ShodashaTheme.tealTint,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.water_drop, color: ShodashaTheme.teal),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: ShodashaTheme.muted,
                ),
              ),
              const Text(
                'Book water',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
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

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return 'GOOD MORNING';
  if (hour >= 17 && hour < 22) return 'GOOD EVENING';
  return 'HELLO';
}

class _ScheduleCards extends StatelessWidget {
  const _ScheduleCards({required this.controller});

  final BookingController controller;

  @override
  Widget build(BuildContext context) {
    final isOnce = controller.deliveryType == DeliveryType.once;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BOOK WATER',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: ShodashaTheme.muted,
          ),
        ),
        const Text(
          'Choose your schedule',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            color: ShodashaTheme.ink,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ScheduleCard(
                title: 'One-time',
                sub: kFixedWindowLabel,
                icon: Icons.bolt_outlined,
                selected: isOnce,
                onTap: () => controller.deliveryType = DeliveryType.once,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ScheduleCard(
                title: 'Daily plan',
                sub: 'Auto refill',
                icon: Icons.repeat,
                selected: !isOnce,
                onTap: () => controller.deliveryType = DeliveryType.daily,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Every day water — fixed morning 8–12 window.',
          style: TextStyle(fontSize: 12, color: ShodashaTheme.muted),
        ),
      ],
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.title,
    required this.sub,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String sub;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? ShodashaTheme.tealTint : ShodashaTheme.surface,
          border: Border.all(
            color: selected ? ShodashaTheme.teal : ShodashaTheme.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: selected ? ShodashaTheme.teal : ShodashaTheme.muted,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                color: ShodashaTheme.ink,
              ),
            ),
            Text(
              sub,
              style: const TextStyle(
                fontSize: 12,
                color: ShodashaTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletStrip extends StatelessWidget {
  const _WalletStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, size: 18, color: ShodashaTheme.teal),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your safety deposit stays safe in the app — see the Wallet '
              'tab.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Honest catalog state: loading, error + retry, or no-catalog explanation.
class _RatesPanel extends StatelessWidget {
  const _RatesPanel({required this.controller});

  final BookingController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.ratesLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ShodashaTheme.surface,
          border: Border.all(color: ShodashaTheme.border),
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text("Loading today's prices…")),
          ],
        ),
      );
    }
    final error = controller.ratesError;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 20,
                color: ShodashaTheme.danger,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Prices are not available',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            error ??
                'Prices load from the server. Check your connection and retry.',
            style: const TextStyle(
              fontSize: 13,
              color: ShodashaTheme.muted,
            ),
          ),
          if (controller.hasCatalog) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: controller.ratesLoading
                  ? null
                  : controller.refreshRates,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StaleRatesBanner extends StatelessWidget {
  const _StaleRatesBanner({required this.controller});

  final BookingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ShodashaTheme.solarTint,
        border: Border.all(color: ShodashaTheme.solarBorder),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: ShodashaTheme.onSolar,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              controller.ratesError ??
                  'Prices may be out of date. Retry before checkout.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (controller.hasCatalog)
            TextButton(
              onPressed:
                  controller.ratesLoading ? null : controller.refreshRates,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

class _EstimateStrip extends StatelessWidget {
  const _EstimateStrip({required this.controller});

  final BookingController controller;

  @override
  Widget build(BuildContext context) {
    final water = controller.waterBillPaise;
    final deposit = controller.depositDuePaise;
    final total = controller.quoteTotalPaise;
    if (water == null || deposit == null || total == null) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ShodashaTheme.tealTint,
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Text(
        'Water ${rupeesLabel(water)} + Deposit ${rupeesLabel(deposit)} = '
        'Total ${rupeesLabel(total)}',
        style: const TextStyle(
          color: ShodashaTheme.ink,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  const _GridCard({required this.sku, required this.onOpen});

  final CatalogSku sku;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${sku.name}, ${rupeesLabel(sku.pricePaise)}, open details',
      child: ExcludeSemantics(
        child: PressScale(
          onTap: onOpen,
          child: Container(
            decoration: BoxDecoration(
              color: ShodashaTheme.surface,
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
                        topLeft: Radius.circular(11),
                        topRight: Radius.circular(11),
                      ),
                      child: Image.asset(
                        sku.asset,
                        height: 124,
                        fit: BoxFit.cover,
                        cacheWidth: 448,
                        errorBuilder: (_, _, _) => Container(
                          height: 124,
                          color: ShodashaTheme.tealTint,
                          child: const Icon(
                            Icons.water_drop,
                            size: 40,
                            color: ShodashaTheme.teal,
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
                              fontWeight: FontWeight.w800,
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
                              color: ShodashaTheme.ink,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sku.tagline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: ShodashaTheme.muted,
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
                      color: ShodashaTheme.teal,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add,
                      color: ShodashaTheme.surface,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    final message = controller.holdBlocked
        ? 'More than 3 jars are on hold — cash on delivery is blocked. '
            'Choose UPI or clear your dues.'
        : 'Dues: ${rupeesLabel(controller.duesPaise)} — this will be added '
            'to your bill.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: ShodashaTheme.blue),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: ShodashaTheme.blue),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

/// N 6–10 bulk quantity confirmation.
Future<bool?> showBulkConfirmDialog(
  BuildContext context, {
  required int total,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: ShodashaTheme.shape,
      title: const Text('Order 6+ jars?'),
      content: Text('$total jars — please confirm the quantity.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text(
            'Go back',
            style: TextStyle(color: ShodashaTheme.muted),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: ShodashaTheme.teal,
            foregroundColor: ShodashaTheme.surface,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}

/// N > 10 tanker sheet: call the vendor — never creates an order.
Future<void> showTankerSheet(
  BuildContext context, {
  Future<bool> Function(Uri url, {LaunchMode mode})? openUrl,
}) {
  Future<void> callVendor(BuildContext ctx) async {
    final digits = kSupportPhone.replaceAll(RegExp(r'\D'), '');
    final open = openUrl ?? launchUrl;
    var ok = false;
    try {
      ok = await open(Uri(scheme: 'tel', path: '+$digits'));
    } catch (_) {
      ok = false;
    }
    if (ok || !ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text('Could not open the dialer — call $kSupportPhone')),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: ShodashaTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ShodashaTheme.radiusSheet),
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
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'More than 10 jars needs a tanker. Talk to the vendor to '
              'arrange it.',
              style: TextStyle(color: ShodashaTheme.muted),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ShodashaTheme.teal,
                  foregroundColor: ShodashaTheme.surface,
                ),
                onPressed: () => callVendor(ctx),
                child: const Text('Call the vendor'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
