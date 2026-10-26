// Donor customer home tab. Visual grammar follows the donor home (teal top
// bar, two mode cards, featured jars, purity card); data is the real catalog /
// address / subscription state owned by the 032 controllers.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui/app_banner.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_card.dart';
import '../addresses/address_screen.dart';
import '../booking/booking_controller.dart';
import 'widgets/featured_products.dart';
import 'widgets/live_purity_card.dart';
import 'widgets/mode_selection_cards.dart';
import 'widgets/top_bar.dart';

class DonorHomeTab extends StatefulWidget {
  const DonorHomeTab({
    super.key,
    required this.api,
    required this.booking,
    required this.addresses,
    required this.onInstantOrder,
    required this.onSubscribe,
    required this.onOpenAddresses,
    required this.onOpenNotifications,
    required this.onOpenProfile,
    required this.onOpenSupport,
    required this.onOpenCart,
    required this.onSearch,
    required this.onOrderProduct,
  });

  final ApiClient api;
  final BookingController booking;
  final AddressController addresses;
  final VoidCallback onInstantOrder;
  final VoidCallback onSubscribe;
  final VoidCallback onOpenAddresses;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenSupport;
  final VoidCallback onOpenCart;
  final VoidCallback onSearch;
  final void Function({required int refill, required int container})
  onOrderProduct;

  @override
  State<DonorHomeTab> createState() => _DonorHomeTabState();
}

class _DonorHomeTabState extends State<DonorHomeTab> {
  @override
  void initState() {
    super.initState();
    widget.booking.ensureCatalog(HttpCatalogApi(widget.api));
    if (!widget.booking.hasRates) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.booking.refreshRates();
      });
    }
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.booking, widget.addresses]),
      builder: (context, _) {
        final selected = widget.addresses.resolve();
        final addressStatus = widget.addresses.status;
        final ratesError = widget.booking.ratesError;
        final ratesOffline =
            ratesError != null && ratesError.toLowerCase().contains('internet');

        return Column(
          children: [
            DonorTopBar(
              addressLabel: selected?.label,
              addressDetail: selected?.addressLine,
              addressLoading:
                  addressStatus == AddrStatus.loading && selected == null,
              addressError:
                  addressStatus == AddrStatus.error && selected == null,
              addressEmpty:
                  addressStatus == AddrStatus.loaded &&
                  widget.addresses.items.isEmpty,
              onRetryAddress: widget.addresses.load,
              cartCount: widget.booking.totalJars,
              onAddressTap: widget.onOpenAddresses,
              onNotifications: widget.onOpenNotifications,
              onProfile: widget.onOpenProfile,
              onCart: widget.onOpenCart,
              onSearch: widget.onSearch,
            ),
            if (ratesOffline)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  0,
                ),
                child: AppBanner.offline(onRetry: widget.booking.refreshRates),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await Future.wait([
                    widget.booking.refreshRates(),
                    widget.addresses.load(),
                  ]);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 28),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.md,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$_greeting,',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: ShodashaTheme.muted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Pure water, delivered.',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.6,
                                    height: 1.15,
                                    color: ShodashaTheme.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: ShodashaTheme.tealTint,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified_outlined,
                                  size: 16,
                                  color: ShodashaTheme.tealDeep,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'RO + UV',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: ShodashaTheme.tealDeep,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: ModeSelectionCards(
                        onInstantOrder: widget.onInstantOrder,
                        onSubscribe: widget.onSubscribe,
                      ),
                    ),
                    if (widget.booking.ratesError != null &&
                        widget.booking.rates != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          0,
                        ),
                        child: AppBanner.stale(
                          message: widget.booking.ratesError,
                          onRetry: widget.booking.refreshRates,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: FeaturedProductsShowcase(
                        rates: widget.booking.rates,
                        loading: widget.booking.ratesLoading,
                        error: widget.booking.ratesError,
                        onRetry: widget.booking.refreshRates,
                        onOrder: widget.onOrderProduct,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const LivePurityCard(),
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: _SupportCard(onTap: widget.onOpenSupport),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: ShodashaTheme.tealTint,
      borderColor: ShodashaTheme.teal.withValues(alpha: 0.22),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ShodashaTheme.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: ShodashaTheme.teal.withValues(alpha: 0.22),
              ),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: ShodashaTheme.tealDeep,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need help with a delivery?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Our Bhopal plant desk is one tap away.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: ShodashaTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          AppButton(
            label: 'Support',
            kind: AppButtonKind.ghost,
            expand: false,
            height: ShodashaTheme.minTarget,
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}
