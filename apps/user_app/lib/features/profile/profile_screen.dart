// S8 — Profile tab: identity card, edit-profile sheet, logout confirm, and
// navigation entries. Support lives in this slice too; addresses, payments
// and returns are other slices, so they arrive as nullable callbacks.
//
// States.md coverage: guest/empty (log-in CTA), loading (identity skeleton),
// error (message + retry), loaded (identity), submitting (edit sheet),
// validation error (inline), success (snackbar), destructive action
// (logout confirmation), unauthorized (session-expired copy).
//
// HARD LAWS: no wallet/ledger/payments/returns UI or money here (S7 owns
// them); green is never used (logout is destructive, not a money CTA);
// every tappable row is >= 48dp; blue is not used for any filled surface.

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../support/support_screen.dart';
import 'edit_profile_sheet.dart';
import 'profile_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.api,
    required this.isAuthenticated,
    this.controller,
    this.onLoginRequired,
    this.onLogout,
    this.onOpenAddresses,
    this.onOpenPayments,
    this.onOpenReturns,
  });

  /// The single authenticated transport from the composition root.
  final ApiClient api;

  /// Guest mode shows the log-in CTA and never fires an authed request.
  final bool isAuthenticated;

  /// Injectable for tests / shell reuse; otherwise created from [api].
  final ProfileController? controller;

  final VoidCallback? onLoginRequired;

  /// Shell owns the AuthController, so logout is a callback (server revoke +
  /// local wipe happen there). Confirmation stays in this screen.
  final Future<void> Function()? onLogout;

  /// S8 owns only the entries — the destination screens belong to other
  /// slices. Null callbacks hide their row (no dead taps).
  final VoidCallback? onOpenAddresses;
  final VoidCallback? onOpenPayments;
  final VoidCallback? onOpenReturns;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController _controller =
      widget.controller ?? ProfileController(api: widget.api);
  late final bool _ownsController = widget.controller == null;

  @override
  void initState() {
    super.initState();
    if (widget.isAuthenticated && _controller.status == ProfileStatus.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _controller.load());
    }
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Lazy-mounted tab: a guest can log in while this screen is alive.
    if (!oldWidget.isAuthenticated &&
        widget.isAuthenticated &&
        _controller.status == ProfileStatus.initial) {
      _controller.load();
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _openEditProfileSheet() async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ShodashaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusSheet),
        ),
      ),
      builder: (_) => EditProfileSheet(controller: _controller),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: ShodashaTheme.shape,
        title: const Text(
          'Log out?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'You will need to log in again to track orders and see your account.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: ShodashaTheme.muted),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: ShodashaTheme.danger),
            child: const Text('Yes, log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onLogout?.call();
  }

  void _openSupport() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SupportScreen(api: widget.api)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAuthenticated) {
      return _GuestView(onLoginRequired: widget.onLoginRequired);
    }
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          const Text(
            'Profile',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: ShodashaTheme.ink,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Your account, payments and support.',
            style: TextStyle(fontSize: 13, color: ShodashaTheme.muted),
          ),
          const SizedBox(height: 18),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _IdentitySection(
              controller: _controller,
              onEdit: _openEditProfileSheet,
            ),
          ),
          if (widget.onOpenAddresses != null ||
              widget.onOpenPayments != null ||
              widget.onOpenReturns != null) ...[
            const _SectionLabel('ACCOUNT'),
            if (widget.onOpenAddresses != null)
              _ServiceTile(
                icon: Icons.location_on_outlined,
                title: 'Saved addresses',
                subtitle: 'Manage your delivery addresses',
                onTap: widget.onOpenAddresses!,
              ),
            if (widget.onOpenPayments != null)
              _ServiceTile(
                icon: Icons.receipt_long_outlined,
                title: 'Payments & deposits',
                subtitle: 'Receipts and deposit history',
                onTap: widget.onOpenPayments!,
              ),
            if (widget.onOpenReturns != null)
              _ServiceTile(
                icon: Icons.undo_outlined,
                title: 'Return jars',
                subtitle: 'Request a pickup and share your UPI ID',
                onTap: widget.onOpenReturns!,
              ),
          ],
          const _SectionLabel('HELP'),
          _ServiceTile(
            icon: Icons.support_agent_outlined,
            title: 'Help & support',
            subtitle: 'WhatsApp, FAQ and complaints',
            onTap: _openSupport,
          ),
          const SizedBox(height: 24),
          _ServiceTile(
            icon: Icons.logout,
            title: 'Log out',
            subtitle: 'Sign out of this device',
            onTap: _confirmLogout,
            iconColor: ShodashaTheme.danger,
            iconBackground: ShodashaTheme.danger.withValues(alpha: 0.10),
            titleColor: ShodashaTheme.danger,
            showChevron: false,
          ),
        ],
      ),
    );
  }
}

/// Guest state (States.md authentication): prices were never walled, but
/// account data is. One action, honest copy, no fake identity.
class _GuestView extends StatelessWidget {
  const _GuestView({this.onLoginRequired});

  final VoidCallback? onLoginRequired;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: ShodashaTheme.tealTint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    size: 36,
                    color: ShodashaTheme.teal,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Log in to view your account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: ShodashaTheme.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Your details, payments and support live here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: ShodashaTheme.muted,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onLoginRequired,
                    style: FilledButton.styleFrom(
                      backgroundColor: ShodashaTheme.teal,
                      foregroundColor: ShodashaTheme.surface,
                      minimumSize: const Size.fromHeight(52),
                      shape: ShodashaTheme.shape,
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Text('Log in'),
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

/// Loading / loaded / error switch for the identity card only — the account
/// and help entries stay usable while the read is in flight.
class _IdentitySection extends StatelessWidget {
  const _IdentitySection({required this.controller, required this.onEdit});

  final ProfileController controller;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    if (controller.user != null) {
      return _IdentityCard(user: controller.user!, onEdit: onEdit);
    }
    if (controller.status == ProfileStatus.error) {
      return _IdentityError(
        message: controller.errorMessage ?? kProfileLoadError,
        onRetry: controller.load,
      );
    }
    // initial + loading without a cached identity → skeleton (never a fake
    // name or phone).
    return const _IdentitySkeleton();
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.user, required this.onEdit});

  final Map<String, dynamic> user;
  final VoidCallback onEdit;

  String _text(String key) {
    final value = user[key];
    return value is String ? value.trim() : '';
  }

  @override
  Widget build(BuildContext context) {
    final name = _text('name');
    final phone = _text('phone');
    final email = _text('email');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: ShodashaTheme.tealTint,
            child: const Icon(
              Icons.person_outline,
              size: 28,
              color: ShodashaTheme.teal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Customer' : name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: ShodashaTheme.ink,
                  ),
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    phone,
                    style: const TextStyle(
                      fontSize: 13,
                      color: ShodashaTheme.muted,
                    ),
                  ),
                ],
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    email,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: ShodashaTheme.muted,
                    ),
                  ),
                ],
                if (phone.isEmpty && email.isEmpty) ...[
                  const SizedBox(height: 2),
                  const Text(
                    'Add your contact details',
                    style: TextStyle(fontSize: 13, color: ShodashaTheme.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(64, ShodashaTheme.minTarget),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text(
              'Edit',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentitySkeleton extends StatelessWidget {
  const _IdentitySkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading profile',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ShodashaTheme.surface,
          border: Border.all(color: ShodashaTheme.border),
          borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: ShodashaTheme.tealTint,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 140,
                    height: 14,
                    decoration: BoxDecoration(
                      color: ShodashaTheme.tealTint,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 110,
                    height: 10,
                    decoration: BoxDecoration(
                      color: ShodashaTheme.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 170,
                    height: 10,
                    decoration: BoxDecoration(
                      color: ShodashaTheme.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityError extends StatelessWidget {
  const _IdentityError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            size: 20,
            color: ShodashaTheme.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: ShodashaTheme.muted,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

/// Section eyebrow — donor rhythm (11/w800 caps), used as a group label,
/// not as decoration above the page title.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: ShodashaTheme.muted,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

/// Donor action-tile grammar: white card, tinted icon chip, chevron. Rows
/// are 68dp tall (>= 48dp law) and the whole row is the tap target.
class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = ShodashaTheme.teal,
    this.iconBackground = ShodashaTheme.tealTint,
    this.titleColor = ShodashaTheme.ink,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color iconColor;
  final Color iconBackground;
  final Color titleColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: ShodashaTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
          side: const BorderSide(color: ShodashaTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconBackground,
                      borderRadius: BorderRadius.circular(
                        ShodashaTheme.radiusSm,
                      ),
                    ),
                    child: Icon(icon, size: 20, color: iconColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: ShodashaTheme.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showChevron)
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: ShodashaTheme.muted,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
