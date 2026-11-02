import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import 'widgets/pod_sheet.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({
    super.key,
    required this.api,
    required this.onLogout,
  });

  final ApiClient api;
  final VoidCallback onLogout;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _stops = [];
  Map<String, dynamic> _summary = {'total': 0, 'delivered': 0, 'pending': 0};
  String _filter = 'pending'; // 'pending' or 'delivered'

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await widget.api.getTodayRoute();
      final stopsRaw = data['stops'] as List<dynamic>? ?? [];
      final summaryRaw = data['summary'] as Map<String, dynamic>? ?? {};

      if (mounted) {
        setState(() {
          _stops = stopsRaw.map((s) => Map<String, dynamic>.from(s as Map)).toList();
          _summary = summaryRaw;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _makeCall(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    if (cleaned.isEmpty) return;
    final uri = Uri.parse('tel:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _openPodSheet(Map<String, dynamic> stop) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ShodashaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ShodashaTheme.radiusLg)),
      ),
      builder: (_) => PodSheet(
        stop: stop,
        api: widget.api,
        onSuccess: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Delivery marked as completed successfully!'),
              backgroundColor: ShodashaTheme.successDark,
            ),
          );
          _loadRoute();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final riderName = widget.api.riderUser?['name']?.toString() ?? 'Rider';
    final total = _summary['total'] as int? ?? 0;
    final delivered = _summary['delivered'] as int? ?? 0;
    final pending = _summary['pending'] as int? ?? 0;

    final visibleStops = _stops.where((s) {
      if (_filter == 'pending') return s['status'] != 'done';
      return s['status'] == 'done';
    }).toList();

    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TODAY\'S DELIVERIES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: ShodashaTheme.muted,
                letterSpacing: 0.8,
              ),
            ),
            Text(
              riderName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ShodashaTheme.ink,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh route',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _loadRoute,
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('End Shift & Log Out?'),
                  content: const Text('Are you sure you want to log out of the rider app?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Stay'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ShodashaTheme.danger,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Log Out'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await widget.api.logout();
                widget.onLogout();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Shift Progress Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            color: ShodashaTheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$delivered of $total Delivered',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                    Text(
                      '$pending Remaining',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ShodashaTheme.tealDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total > 0 ? (delivered / total) : 0,
                    minHeight: 6,
                    backgroundColor: ShodashaTheme.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(ShodashaTheme.teal),
                  ),
                ),
              ],
            ),
          ),

          // Filter Segmented Tabs
          Container(
            color: ShodashaTheme.surface,
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: _FilterTab(
                    label: 'Pending ($pending)',
                    active: _filter == 'pending',
                    onTap: () => setState(() => _filter = 'pending'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _FilterTab(
                    label: 'Delivered ($delivered)',
                    active: _filter == 'delivered',
                    onTap: () => setState(() => _filter = 'delivered'),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: ShodashaTheme.border),

          // List Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  color: ShodashaTheme.danger, size: 40),
                              const SizedBox(height: AppSpacing.sm),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: AppSpacing.md),
                              AppButton(
                                label: 'Retry',
                                onPressed: _loadRoute,
                              ),
                            ],
                          ),
                        ),
                      )
                    : visibleStops.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xl),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _filter == 'pending'
                                        ? Icons.check_circle_outline_rounded
                                        : Icons.inbox_outlined,
                                    size: 48,
                                    color: ShodashaTheme.muted,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Text(
                                    _filter == 'pending'
                                        ? 'All deliveries completed for today!'
                                        : 'No completed deliveries yet.',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: ShodashaTheme.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadRoute,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              itemCount: visibleStops.length,
                              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                              itemBuilder: (context, i) {
                                final stop = visibleStops[i];
                                final isDelivered = stop['status'] == 'done';
                                final customerName = stop['customer_name']?.toString() ?? 'Customer';
                                final phone = stop['customer_phone']?.toString() ?? '';
                                final qty = stop['quantity']?.toString() ?? '1';
                                final address = (stop['address'] as Map<String, dynamic>?) ?? {};
                                final formatted = address['formatted']?.toString() ?? 'Delivery address';
                                final landmark = address['landmark']?.toString() ?? '';
                                final hasLift = address['has_lift'] == true;
                                final isCod = stop['payment_mode'] == 'cod';
                                final amountDue = stop['amount_due'] as int? ?? 0;

                                return Container(
                                  decoration: BoxDecoration(
                                    color: ShodashaTheme.surface,
                                    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                                    border: Border.all(
                                      color: isDelivered ? ShodashaTheme.border : ShodashaTheme.border,
                                    ),
                                    boxShadow: const [ShodashaTheme.subtleCardShadow],
                                  ),
                                  padding: const EdgeInsets.all(AppSpacing.lg),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Top row: Stop Seq + Name + Call
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isDelivered
                                                  ? ShodashaTheme.border
                                                  : ShodashaTheme.tealTint,
                                              borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                                            ),
                                            child: Text(
                                              '#${stop['seq'] ?? (i + 1)}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: isDelivered
                                                    ? ShodashaTheme.muted
                                                    : ShodashaTheme.tealDark,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  customerName,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                    color: isDelivered
                                                        ? ShodashaTheme.muted
                                                        : ShodashaTheme.ink,
                                                  ),
                                                ),
                                                if (phone.isNotEmpty) ...[
                                                  const SizedBox(height: 1),
                                                  Text(
                                                    phone,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: ShodashaTheme.muted,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (phone.isNotEmpty)
                                            IconButton(
                                              tooltip: 'Call customer',
                                              onPressed: () => _makeCall(phone),
                                              icon: const Icon(Icons.call_rounded),
                                              color: ShodashaTheme.teal,
                                            ),
                                        ],
                                      ),

                                      const SizedBox(height: AppSpacing.sm),

                                      // Full address
                                      Text(
                                        formatted,
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.3,
                                          color: isDelivered
                                              ? ShodashaTheme.muted
                                              : ShodashaTheme.ink,
                                        ),
                                      ),

                                      if (landmark.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Landmark: $landmark',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: ShodashaTheme.muted,
                                          ),
                                        ),
                                      ],

                                      const SizedBox(height: AppSpacing.sm),

                                      // Badges Row: 20L Cane Quantity + Lift + Payment
                                      Wrap(
                                        spacing: AppSpacing.xs,
                                        runSpacing: AppSpacing.xs,
                                        children: [
                                          // Quantity badge
                                          _Badge(
                                            label: '$qty × 20L Cane',
                                            bg: ShodashaTheme.tealTint,
                                            fg: ShodashaTheme.tealDark,
                                            icon: Icons.water_drop_rounded,
                                          ),

                                          // Lift badge
                                          if (hasLift)
                                            const _Badge(
                                              label: 'Lift Available',
                                              bg: ShodashaTheme.successTint,
                                              fg: ShodashaTheme.successDark,
                                              icon: Icons.elevator_rounded,
                                            )
                                          else
                                            const _Badge(
                                              label: 'No Lift (Stairs)',
                                              bg: ShodashaTheme.warningTint,
                                              fg: ShodashaTheme.warningDark,
                                              icon: Icons.stairs_rounded,
                                            ),

                                          // Payment badge
                                          if (isCod && amountDue > 0)
                                            _Badge(
                                              label: 'Collect ₹${(amountDue / 100).toStringAsFixed(0)} Cash',
                                              bg: ShodashaTheme.warningTint,
                                              fg: ShodashaTheme.warningDark,
                                              icon: Icons.payments_rounded,
                                            )
                                          else
                                            const _Badge(
                                              label: 'Paid Online',
                                              bg: ShodashaTheme.successTint,
                                              fg: ShodashaTheme.successDark,
                                              icon: Icons.check_circle_outline_rounded,
                                            ),
                                        ],
                                      ),

                                      const SizedBox(height: AppSpacing.md),

                                      // Bottom Action
                                      if (isDelivered)
                                        const Row(
                                          children: [
                                            Icon(Icons.check_circle_rounded,
                                                color: ShodashaTheme.successDark, size: 18),
                                            SizedBox(width: AppSpacing.xs),
                                            Text(
                                              'Delivered successfully',
                                              style: TextStyle(
                                                color: ShodashaTheme.successDark,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        SizedBox(
                                          width: double.infinity,
                                          child: AppButton(
                                            label: 'Mark Delivered (Enter OTP)',
                                            kind: AppButtonKind.primary,
                                            icon: Icons.key_rounded,
                                            onPressed: () => _openPodSheet(stop),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? ShodashaTheme.tealTint : Colors.transparent,
          borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
          border: Border.all(
            color: active ? ShodashaTheme.teal : ShodashaTheme.border,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: active ? ShodashaTheme.tealDark : ShodashaTheme.muted,
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.bg,
    required this.fg,
    required this.icon,
  });

  final String label;
  final Color bg;
  final Color fg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

