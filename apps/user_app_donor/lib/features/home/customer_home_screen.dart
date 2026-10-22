// Donor customer home tab. Visual grammar follows the donor home (teal top
// bar, two mode cards, featured jars, purity card); data is the real catalog /
// address / subscription state owned by the 032 controllers.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/constants/app_constants.dart';
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
        return Column(
          children: [
            DonorTopBar(
              addressLabel: selected?.label,
              addressDetail: selected?.addressLine,
              cartCount: widget.booking.totalJars,
              onAddressTap: widget.onOpenAddresses,
              onNotifications: widget.onOpenNotifications,
              onProfile: widget.onOpenProfile,
              onCart: widget.onOpenCart,
              onSearch: widget.onSearch,
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
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$_greeting,',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                const Text(
                                  'Pure water, delivered.',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.verified,
                                  size: 14,
                                  color: Color(0xFF15803D),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'RO + UV',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF15803D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ModeSelectionCards(
                        onInstantOrder: widget.onInstantOrder,
                        onSubscribe: widget.onSubscribe,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FeaturedProductsShowcase(
                        rates: widget.booking.rates,
                        loading: widget.booking.ratesLoading,
                        error: widget.booking.ratesError,
                        onRetry: widget.booking.refreshRates,
                        onOrder: widget.onOrderProduct,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const LivePurityCard(),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.support_agent,
                              color: AppColors.primary,
                              size: 26,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Need help with a delivery?',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Our Bhopal plant desk is one tap away.',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: widget.onOpenProfile,
                              child: const Text(
                                'PROFILE',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
