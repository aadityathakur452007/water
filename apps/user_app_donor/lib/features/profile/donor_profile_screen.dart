// Donor profile screen, backed by GET /auth/me. The donor version hardcoded
// "Rahul Sharma", a fake order count and a local notification list. Here the
// identity comes from the profile controller; the only unread state shown is
// derived from real orders/subscriptions by the notifications screen.

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../addresses/address_screen.dart';
import '../auth/auth_controller.dart';
import 'edit_profile_sheet.dart';
import 'profile_controller.dart';

class DonorProfileScreen extends StatefulWidget {
  const DonorProfileScreen({
    super.key,
    required this.auth,
    required this.controller,
    required this.addressController,
    required this.orderCount,
    required this.onOpenWallet,
    required this.onOpenNotifications,
    required this.onOpenSupport,
    required this.onOpenSubscriptions,
  });

  final AuthController auth;
  final ProfileController controller;
  final AddressController addressController;
  final int orderCount;
  final VoidCallback onOpenWallet;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenSupport;
  final VoidCallback onOpenSubscriptions;

  @override
  State<DonorProfileScreen> createState() => _DonorProfileScreenState();
}

class _DonorProfileScreenState extends State<DonorProfileScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.status == ProfileStatus.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.load();
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      widget.controller.load(),
      widget.addressController.load(),
    ]);
  }

  Future<void> _edit() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EditProfileSheet(controller: widget.controller),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    }
  }

  Future<void> _openAddresses() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AddressScreen(controller: widget.addressController),
      ),
    );
    if (mounted) await widget.addressController.load();
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need your phone OTP to sign in again. Your orders and '
          'deposit stay safe on the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'MY PROFILE',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: Colors.white,
            letterSpacing: 1.1,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          widget.controller,
          widget.addressController,
        ]),
        builder: (context, _) {
          final user = widget.controller.user;
          final name = _text(user, 'name');
          final phone = _text(user, 'phone');
          final email = _text(user, 'email');
          final addresses = widget.addressController.items.length;
          final initials = _initials(name.isEmpty ? 'Shodasha Customer' : name);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.12,
                            ),
                            child: Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? 'Shodasha customer' : name,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.3,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  phone.isEmpty ? 'Phone on file' : phone,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                if (email.isNotEmpty)
                                  Text(
                                    email,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit profile',
                            onPressed: _edit,
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _stat('${widget.orderCount}', 'Orders'),
                            Container(
                              height: 28,
                              width: 1,
                              color: AppColors.border,
                            ),
                            _stat('$addresses', 'Addresses'),
                            Container(
                              height: 28,
                              width: 1,
                              color: AppColors.border,
                            ),
                            _stat(
                              widget.auth.isAuthenticated ? 'Active' : '—',
                              'Session',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.controller.status == ProfileStatus.error) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.controller.errorMessage ??
                        'Could not load your profile.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB91C1C),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'ACCOUNT',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                _menuTile(
                  icon: Icons.location_on_outlined,
                  title: 'Saved addresses',
                  subtitle: addresses == 0
                      ? 'Add a delivery address'
                      : '$addresses saved',
                  onTap: _openAddresses,
                ),
                _menuTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Shodasha wallet',
                  subtitle: 'Deposits, dues and receipts',
                  onTap: widget.onOpenWallet,
                ),
                _menuTile(
                  icon: Icons.autorenew,
                  title: 'My subscriptions',
                  subtitle: 'Plans, skips and dues',
                  onTap: widget.onOpenSubscriptions,
                ),
                _menuTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Order and subscription updates',
                  onTap: widget.onOpenNotifications,
                ),
                const SizedBox(height: 18),
                const Text(
                  'SUPPORT',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                _menuTile(
                  icon: Icons.headset_mic_outlined,
                  title: 'Help & support',
                  subtitle: 'Call, WhatsApp or raise a complaint',
                  onTap: widget.onOpenSupport,
                ),
                _menuTile(
                  icon: Icons.verified_outlined,
                  title: 'Water quality',
                  subtitle: 'RO + UV + Ozone · 20L sealed jars',
                  onTap: () => _showQuality(),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _logout,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text(
                    'LOG OUT',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showQuality() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Water quality',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 12),
            Text(
              'Every Shodasha 20L jar is purified through a 9-stage RO + UV + '
              'ozone process and sealed in a food-grade jar. Batch lab reports '
              'are available from support on request. The app does not display '
              'live plant telemetry because the API does not expose it.',
              style: TextStyle(
                height: 1.5,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          height: 38,
          width: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: Color(0xFF94A3B8),
          size: 20,
        ),
        onTap: onTap,
      ),
    );
  }
}

String _text(Map<String, dynamic>? user, String key) {
  final value = user?[key];
  return value is String ? value.trim() : '';
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  final letters = parts.where((p) => p.isNotEmpty).take(2).map((p) => p[0]);
  return letters.join().toUpperCase();
}
