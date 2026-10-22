// Donor top bar, wired to real state. The donor version kept a local address
// list, fake GPS entries and a fixed cart badge; all three are removed. The
// address comes from GET /addresses, search filters the server catalog, and
// the badge is the current checkout jar count (zero hides it).

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';

class DonorTopBar extends StatelessWidget {
  const DonorTopBar({
    super.key,
    required this.addressLabel,
    required this.addressDetail,
    required this.cartCount,
    required this.onAddressTap,
    required this.onNotifications,
    required this.onProfile,
    required this.onCart,
    required this.onSearch,
  });

  final String? addressLabel;
  final String? addressDetail;
  final int cartCount;
  final VoidCallback onAddressTap;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final VoidCallback onCart;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final hasAddress = (addressLabel ?? '').trim().isNotEmpty;
    final line = hasAddress
        ? 'DELIVERY: ${addressLabel!.toUpperCase()}'
        : 'ADD A DELIVERY ADDRESS';

    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.water_drop, color: Colors.white, size: 26),
                  SizedBox(width: 8),
                  Text(
                    'SHODASHA',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  _circleButton(
                    icon: Icons.notifications_outlined,
                    tooltip: 'Notifications',
                    onTap: onNotifications,
                  ),
                  const SizedBox(width: 8),
                  _circleButton(
                    icon: Icons.person,
                    tooltip: 'Profile',
                    onTap: onProfile,
                  ),
                  const SizedBox(width: 8),
                  _circleButton(
                    icon: Icons.shopping_cart_outlined,
                    tooltip: 'Checkout',
                    onTap: onCart,
                    badge: cartCount > 0 ? '$cartCount' : null,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: onAddressTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Colors.white70,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (hasAddress &&
                            (addressDetail ?? '').trim().isNotEmpty)
                          Text(
                            addressDetail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white70,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onSearch,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: const Row(
                  children: [
                    Icon(
                      Icons.search,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Search water cans...',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Container(
      height: 36,
      width: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            tooltip: tooltip,
            icon: Icon(icon, color: Colors.white, size: 20),
            onPressed: onTap,
          ),
          if (badge != null)
            Positioned(
              right: 3,
              top: 3,
              child: Container(
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badge,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textOnAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
