// Donor profile screen, backed by GET /auth/me. The donor version hardcoded
// "Rahul Sharma", a fake order count and a local notification list. Here the
// identity comes from the profile controller; the only unread state shown is
// derived from real orders/subscriptions by the notifications screen.

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme.dart';
import '../../shared/ui/app_banner.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_card.dart';
import '../../shared/ui/app_sheet.dart';
import '../../shared/ui/app_state_view.dart';
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
  bool _loggingOut = false;

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
      enableDrag: false,
      backgroundColor: ShodashaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusSheet),
        ),
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
    if (_loggingOut) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need your mobile number and password to sign in again. '
          'Your orders and deposit stay safe on the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, ShodashaTheme.minTarget),
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: ShodashaTheme.danger,
              foregroundColor: ShodashaTheme.surface,
              minimumSize: const Size(48, ShodashaTheme.minTarget),
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loggingOut = true);
    await widget.auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(
        backgroundColor: ShodashaTheme.tealDeep,
        foregroundColor: ShodashaTheme.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: ShodashaTheme.surface,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh profile',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
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
          final initials = _initials(name.isEmpty ? 'Shodasha' : name);
          final loading =
              user == null &&
              (widget.controller.status == ProfileStatus.initial ||
                  widget.controller.status == ProfileStatus.loading);
          final loadFailed =
              user == null && widget.controller.status == ProfileStatus.error;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              children: [
                if (loading)
                  const _ProfileSkeleton()
                else if (loadFailed)
                  _ProfileError(
                    message:
                        widget.controller.errorMessage ??
                        'Could not load your profile.',
                    onRetry: _refresh,
                  )
                else
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
                                    name.isEmpty ? 'Your profile' : name,
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.3,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  if (phone.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      phone,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
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
                if (widget.controller.status == ProfileStatus.error &&
                    user != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppBanner.stale(
                    message:
                        widget.controller.errorMessage ??
                        'Could not refresh your profile.',
                    onRetry: _refresh,
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                const Text(
                  'Account',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.muted,
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
                const SizedBox(height: AppSpacing.xl),
                const Text(
                  'Support',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.muted,
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
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: _loggingOut ? 'Logging out…' : 'Log out',
                  kind: AppButtonKind.danger,
                  icon: Icons.logout_rounded,
                  busy: _loggingOut,
                  onPressed: _logout,
                ),
                const SizedBox(height: AppSpacing.xl),
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
      isScrollControlled: true,
      backgroundColor: ShodashaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusSheet),
        ),
      ),
      builder: (ctx) => AppSheet(
        title: 'Water quality',
        onClose: () => Navigator.of(ctx).pop(),
        footer: AppButton(
          label: 'Close',
          kind: AppButtonKind.secondary,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        child: const Text(
          'Every Shodasha 20L jar is purified through a 9-stage RO + UV + '
          'ozone process and sealed in a food-grade jar. Batch lab reports '
          'are available from support on request. The app does not display '
          'live plant telemetry because the API does not expose it.',
          style: TextStyle(height: 1.5, fontSize: 14, color: ShodashaTheme.ink),
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
            fontWeight: FontWeight.w800,
            color: ShodashaTheme.tealDeep,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ShodashaTheme.minTarget),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: ShodashaTheme.tealTint,
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                ),
                child: Icon(icon, color: ShodashaTheme.tealDeep, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
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
              const Icon(
                Icons.chevron_right_rounded,
                color: ShodashaTheme.muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ShodashaTheme.skeleton,
        borderRadius: BorderRadius.circular(8),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
        border: Border.all(color: ShodashaTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: ShodashaTheme.skeleton,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  box(150, 16),
                  const SizedBox(height: 8),
                  box(110, 12),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          box(double.infinity, 42),
        ],
      ),
    );
  }
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return AppStateView.error(
      title: 'Profile unavailable',
      message: message,
      onRetry: onRetry,
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
