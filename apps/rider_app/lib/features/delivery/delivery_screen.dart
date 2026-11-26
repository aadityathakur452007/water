import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import 'widgets/pod_sheet.dart';

part 'widgets/delivery_badges.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.api, required this.onLogout});

  final ApiClient api;
  final VoidCallback onLogout;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _stops = [];
  Map<String, dynamic> _summary = {'total': 0, 'delivered': 0, 'pending': 0};
  String _dutyStatus = 'on_duty';
  String _filter = 'pending'; // 'pending' or 'delivered'
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRoute();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _dutyStatus == 'on_duty' && !_loading) {
        _loadRoute(silent: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadRoute(silent: true);
      _startPolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pollTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRoute({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await widget.api.getTodayRoute();
      final stopsRaw = data['stops'] as List<dynamic>? ?? [];
      final summaryRaw = data['summary'] as Map<String, dynamic>? ?? {};
      final dutyStatus = (data['duty_status'] as String?) ?? 'on_duty';

      if (mounted) {
        setState(() {
          _stops = stopsRaw
              .map((s) => Map<String, dynamic>.from(s as Map))
              .toList();
          _summary = summaryRaw;
          _dutyStatus = dutyStatus;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _makeCall(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    final dialTarget = digits.length == 10 ? '+91$digits' : '+$digits';
    final uri = Uri.parse('tel:$dialTarget');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _navigateToLocation(String address) async {
    if (address.isEmpty) return;
    final query = Uri.encodeComponent(address);
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openPodSheet(Map<String, dynamic> stop) {
    if (_dutyStatus != 'on_duty') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are off-duty. Switch on duty to deliver stops.'),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ShodashaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusLg),
        ),
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

  Future<void> _openCancelDialog(Map<String, dynamic> stop) async {
    final otpCtrl = TextEditingController();
    String reason = 'CUSTOMER_UNREACHABLE';
    String? error;
    bool busy = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Text('Cancel Order (ऑर्डर रद्द करें)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ऑर्डर रद्द करने के लिए पहले अपने वेंडर से 4-अंकीय कैंसिलेशन OTP प्राप्त करें:',
                  style: TextStyle(fontSize: 13, color: ShodashaTheme.muted),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'Cancellation OTP (4-digit)',
                    hintText: 'Enter OTP from Vendor',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(
                    labelText: 'Reason (वजह)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'CUSTOMER_UNREACHABLE',
                      child: Text('Customer unreachable / fake'),
                    ),
                    DropdownMenuItem(
                      value: 'DOOR_LOCKED',
                      child: Text('Door locked / no one home'),
                    ),
                    DropdownMenuItem(
                      value: 'CUSTOMER_REFUSED',
                      child: Text('Customer refused order'),
                    ),
                    DropdownMenuItem(
                      value: 'INCORRECT_ADDRESS',
                      child: Text('Incorrect address / not found'),
                    ),
                  ],
                  onChanged: (v) => setDState(() => reason = v ?? 'CUSTOMER_UNREACHABLE'),
                ),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: ShodashaTheme.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Back'),
            ),
            AppButton(
              label: busy ? 'Cancelling…' : 'Confirm Cancel',
              kind: AppButtonKind.danger,
              onPressed: busy
                  ? null
                  : () async {
                      final otp = otpCtrl.text.trim();
                      if (otp.length < 4) {
                        setDState(() => error = 'Enter valid 4-digit OTP from vendor');
                        return;
                      }
                      setDState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await widget.api.cancelDelivery(
                          stopId: stop['id'].toString(),
                          cancelOtp: otp,
                          reason: reason,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Order cancelled successfully!'),
                              backgroundColor: ShodashaTheme.danger,
                            ),
                          );
                          _loadRoute();
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setDState(() {
                            busy = false;
                            error = e is ApiException
                                ? e.message
                                : e.toString().replaceFirst('Exception: ', '');
                          });
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  bool _dutyBusy = false;

  Future<void> _toggleDuty() async {
    if (_dutyBusy) return;
    final next = _dutyStatus == 'on_duty' ? 'off_duty' : 'on_duty';
    setState(() => _dutyBusy = true);
    try {
      final res = await widget.api.setDuty(next);
      if (mounted) {
        setState(() {
          _dutyStatus = (res['duty_status'] as String?) ?? next;
          _dutyBusy = false;
        });
        if (_dutyStatus == 'on_duty') {
          _startPolling();
          _loadRoute(silent: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _dutyBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final riderName = widget.api.riderUser?['name']?.toString() ?? 'Rider';
    final total = _summary['total'] as int? ?? 0;
    final delivered = _summary['delivered'] as int? ?? 0;
    final pending = _summary['pending'] as int? ?? 0;
    final closedCount = _stops.where((s) => s['status'] != 'pending').length;

    final visibleStops = _stops.where((s) {
      if (_filter == 'pending') return s['status'] == 'pending';
      return s['status'] != 'pending';
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
                  content: const Text(
                    'Are you sure you want to log out of the rider app?',
                  ),
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
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            color: ShodashaTheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$delivered of $total Delivered',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: ShodashaTheme.ink,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        InkWell(
                          onTap: _dutyBusy ? null : _toggleDuty,
                          borderRadius: BorderRadius.circular(
                            ShodashaTheme.radiusSm,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _dutyStatus == 'on_duty'
                                  ? ShodashaTheme.tealTint
                                  : ShodashaTheme.warningTint,
                              borderRadius: BorderRadius.circular(
                                ShodashaTheme.radiusSm,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _dutyStatus == 'on_duty' ? 'ON DUTY' : 'OFF DUTY · Tap to start',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: _dutyStatus == 'on_duty'
                                        ? ShodashaTheme.teal
                                        : ShodashaTheme.warningDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      ShodashaTheme.teal,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Filter Segmented Tabs
          Container(
            color: ShodashaTheme.surface,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
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
                    label: 'Completed ($closedCount)',
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
                          const Icon(
                            Icons.error_outline_rounded,
                            color: ShodashaTheme.danger,
                            size: 40,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: AppSpacing.md),
                          AppButton(label: 'Retry', onPressed: _loadRoute),
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
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, i) {
                        final stop = visibleStops[i];
                        final isDelivered = stop['status'] == 'done';
                        final isCancelled = stop['status'] == 'cancelled' ||
                            stop['order_state'] == 'cancelled';
                        final isFailed = stop['status'] == 'failed';
                        final customerName =
                            stop['customer_name']?.toString() ?? 'Customer';
                        final phone = stop['customer_phone']?.toString() ?? '';
                        final qty = stop['quantity']?.toString() ?? '1';
                        final address =
                            (stop['address'] as Map<String, dynamic>?) ?? {};
                        final formatted =
                            address['formatted']?.toString() ??
                            'Delivery address';
                        final landmark = address['landmark']?.toString() ?? '';
                        final hasLift = address['has_lift'] == true;
                        final amountDue = stop['amount_due'] as int? ?? 0;

                        return Container(
                          decoration: BoxDecoration(
                            color: isCancelled
                                ? const Color(0xFFFFF5F5)
                                : ShodashaTheme.surface,
                            borderRadius: BorderRadius.circular(
                              ShodashaTheme.radius,
                            ),
                            border: Border.all(
                              color: isCancelled
                                  ? ShodashaTheme.danger.withValues(alpha: 0.5)
                                  : isDelivered
                                      ? ShodashaTheme.border
                                      : ShodashaTheme.border,
                              width: isCancelled ? 1.5 : 1.0,
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDelivered
                                          ? ShodashaTheme.border
                                          : ShodashaTheme.tealTint,
                                      borderRadius: BorderRadius.circular(
                                        ShodashaTheme.radiusSm,
                                      ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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

                                  // Payment badge with zero-confusion mode resolution
                                  switch (resolveHandoverMode(stop)) {
                                    HandoverMode.dailySubscription =>
                                      const _Badge(
                                        label: 'Monthly Plan (₹0 Cash)',
                                        bg: ShodashaTheme.tealTint,
                                        fg: ShodashaTheme.tealDark,
                                        icon: Icons.calendar_month_rounded,
                                      ),
                                    HandoverMode.monthEndDues =>
                                      _Badge(
                                        label:
                                            'Collect Month Dues: ₹${(amountDue / 100).toStringAsFixed(0)}',
                                        bg: ShodashaTheme.warningTint,
                                        fg: ShodashaTheme.warningDark,
                                        icon: Icons.payments_rounded,
                                      ),
                                    HandoverMode.standardCod =>
                                      _Badge(
                                        label:
                                            'Collect ₹${(amountDue / 100).toStringAsFixed(0)} Cash',
                                        bg: ShodashaTheme.warningTint,
                                        fg: ShodashaTheme.warningDark,
                                        icon: Icons.payments_rounded,
                                      ),
                                    HandoverMode.prepaid =>
                                      const _Badge(
                                        label: 'Paid Online (₹0 Cash)',
                                        bg: ShodashaTheme.successTint,
                                        fg: ShodashaTheme.successDark,
                                        icon: Icons.check_circle_outline_rounded,
                                      ),
                                  },
                                ],
                              ),

                              const SizedBox(height: AppSpacing.md),

                              // Bottom Action
                              if (isDelivered)
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: ShodashaTheme.successDark,
                                      size: 18,
                                    ),
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
                              else if (isCancelled)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: ShodashaTheme.danger.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                                    border: Border.all(color: ShodashaTheme.danger, width: 1.5),
                                  ),
                                  child: const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.block_rounded,
                                            color: ShodashaTheme.danger,
                                            size: 20,
                                          ),
                                          SizedBox(width: AppSpacing.xs),
                                          Expanded(
                                            child: Text(
                                              'DO NOT DELIVER — ORDER CANCELLED',
                                              style: TextStyle(
                                                color: ShodashaTheme.danger,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 13,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'ग्राहक ने ऑर्डर रद्द कर दिया है। जार वापस वाहन स्टॉक में रखें।\n(Customer cancelled this order. Return jar to vehicle stock.)',
                                        style: TextStyle(
                                          color: ShodashaTheme.danger,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (isFailed)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ShodashaTheme.danger
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(
                                      ShodashaTheme.radiusSm,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: ShodashaTheme.danger,
                                        size: 16,
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      Expanded(
                                        child: Text(
                                          'Failed: ${stop['failure_reason'] ?? 'Not delivered'}',
                                          style: const TextStyle(
                                            color: ShodashaTheme.danger,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: AppButton(
                                            label: 'Navigate',
                                            kind: AppButtonKind.secondary,
                                            icon: Icons.navigation_rounded,
                                            onPressed: () =>
                                                _navigateToLocation(formatted),
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        Expanded(
                                          flex: 2,
                                          child: AppButton(
                                            label: 'Mark Delivered (Enter OTP)',
                                            kind: AppButtonKind.primary,
                                            icon: Icons.key_rounded,
                                            onPressed: () => _openPodSheet(stop),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: () => _openCancelDialog(stop),
                                        icon: const Icon(
                                          Icons.cancel_outlined,
                                          size: 16,
                                          color: ShodashaTheme.danger,
                                        ),
                                        label: const Text(
                                          'Cancel Order (ऑर्डर रद्द करें)',
                                          style: TextStyle(
                                            color: ShodashaTheme.danger,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
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

