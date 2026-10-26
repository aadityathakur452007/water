// S5 — Tracking screen (custom 4-step solid dots + connectors, no live dot).
// Contract §4.4 + user-flows flow 3 (window + rider + call, map only near
// arrival — never in v1).
//
// Ported from apps/user_app_legacy_flutter F4 with the donor status
// treatment on tokens only — teal tracker + live banners, slate inset for
// the delivery-code chip, tint schedule row. Frozen on purpose: the
// delivery-code reveal behavior + strings, every order/status string, and the
// verification/poll wiring (60s backoff → 300s cap).
//
// States.md covered: loading (tracker-shaped skeleton), error + retry,
// refreshing (poll), live/assigned banners, failed/rejected/cancelled,
// delivered, action busy, dialer/WhatsApp launch failure.
//
// Visibility matrix: pre-dispatch → Cancel + Reschedule (confirm dialogs);
// dispatched → WhatsApp CTA only; delivered → help row + rate once
// (auto-popup on first view + manual button); cancelled → none.
//
// `onSupport` is the nullable S8 complaints door (no feature-folder import);
// the rating sheet shows its complaint shortcut only when it is wired.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_card.dart';
import '../../shared/ui/app_sheet.dart';
import '../../shared/ui/app_state_view.dart';
import '../../shared/ui/status_pill.dart';
import 'bill_screen.dart';
import 'orders_controller.dart';
import 'rating_sheet.dart';

String _dayLabel(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

String _shortDayLabel(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[d.weekday - 1]} ${d.day}';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Order detail + tracker. Polls via [OrdersController.startTracking].
class TrackingScreen extends StatefulWidget {
  const TrackingScreen({
    super.key,
    required this.controller,
    required this.orderId,
    this.onSupport,
  });

  final OrdersController controller;
  final String orderId;
  final VoidCallback? onSupport;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with WidgetsBindingObserver {
  CancelReason _cancelReason = CancelReason.changedMind;
  bool _ratingShown = false;
  bool _detailLoading = false;
  DateTime _now = DateTime.now();
  Timer? _codeTimer;
  String? _reissueError;
  bool _pushingBill = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detailLoading = widget.controller.findById(widget.orderId) == null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.refreshOrder(widget.orderId);
      // A fast back can dispose this screen mid-refresh; never arm a poll
      // loop for a screen that is already gone.
      if (!mounted) return;
      if (_detailLoading) {
        setState(() => _detailLoading = false);
      }
      widget.controller.startTracking(widget.orderId);
      _maybeAutoRate();
      _syncCodeTimer();
    });
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    _maybeAutoRate();
    _syncCodeTimer();
  }

  /// A 24h code needs a visible rollover while this screen stays open, but a
  /// per-second timer would be wasteful. Recompute a few times a minute and
  /// immediately on app resume.
  void _syncCodeTimer() {
    final order = widget.controller.findById(widget.orderId);
    final needsTick =
        order != null &&
        order.deliveryCodeState == 'active' &&
        order.deliveryCodeExpiresAt != null &&
        order.deliveryCodeExpiresAt!.isAfter(DateTime.now());
    if (!needsTick) {
      _codeTimer?.cancel();
      _codeTimer = null;
      return;
    }
    _codeTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _syncCodeTimer();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _now = DateTime.now());
      _syncCodeTimer();
      widget.controller.resumeTracking();
      widget.controller.refreshOrder(widget.orderId);
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      widget.controller.pauseTracking();
    }
  }

  /// Detail-only retry: re-read this order instead of the whole list.
  Future<void> _retryDetail() async {
    if (_detailLoading) return;
    setState(() => _detailLoading = true);
    await widget.controller.refreshOrder(widget.orderId);
    if (!mounted) return;
    setState(() => _detailLoading = false);
  }

  Future<void> _reissueCode() async {
    if (widget.controller.reissueBusy) return;
    setState(() => _reissueError = null);
    final result = await widget.controller.reissueDeliveryCode(widget.orderId);
    if (!mounted) return;
    if (result.ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('New code ready.')));
      return;
    }
    setState(() => _reissueError = result.message);
  }

  void _maybeAutoRate() {
    if (_ratingShown || !mounted) return;
    final order = widget.controller.findById(widget.orderId);
    if (order == null) return;
    if (!widget.controller.shouldAutoPrompt(order)) return;
    _ratingShown = true;
    widget.controller.markRatingPrompted(order.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showRatingSheet(
        context,
        widget.controller,
        order,
        onSupport: widget.onSupport,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeTimer?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.stopTracking();
    super.dispose();
  }

  Future<void> _confirmCancel(Order order) async {
    _cancelReason = CancelReason.changedMind;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ShodashaTheme.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        title: Text(
          ordersStringsHi['cancelTitle']!,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: ShodashaTheme.ink,
          ),
        ),
        content: StatefulBuilder(
          builder: (ctx, setD) => DropdownButtonFormField<CancelReason>(
            initialValue: _cancelReason,
            decoration: InputDecoration(
              labelText: ordersStringsHi['cancelReasonLabel'],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ShodashaTheme.radius),
              ),
            ),
            items: [
              for (final r in CancelReason.values)
                DropdownMenuItem(value: r, child: Text(r.label)),
            ],
            onChanged: (v) {
              if (v != null) setD(() => _cancelReason = v);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: ShodashaTheme.muted,
              minimumSize: const Size(48, ShodashaTheme.minTarget),
            ),
            child: Text(ordersStringsHi['cancelKeep']!),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ShodashaTheme.ink,
              foregroundColor: ShodashaTheme.bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ShodashaTheme.radius),
              ),
            ),
            child: Text(ordersStringsHi['cancelConfirm']!),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await widget.controller.cancel(order.id, _cancelReason.code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? ordersStringsHi['cancelledBanner']!
              : ordersStringsHi['cancelFailed']!,
        ),
      ),
    );
  }

  Future<void> _confirmReschedule(Order order) async {
    final days = nextServiceDays();
    if (days.isEmpty) return;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var selectedDay = days.first;
        RescheduleSlot? selected;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final slots = serviceSlotsForDay(selectedDay);
            return AppSheet(
              title: ordersStringsHi['rescheduleTitle']!,
              onClose: () => Navigator.of(ctx).pop(),
              footer: AppButton(
                label: 'Confirm new time',
                onPressed: selected == null
                    ? null
                    : () => Navigator.of(ctx).pop(selected!.start),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose a day',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final day in days) ...[
                          ChoiceChip(
                            label: Text(_shortDayLabel(day)),
                            selected: _sameDay(day, selectedDay),
                            showCheckmark: false,
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            selectedColor: ShodashaTheme.tealTint,
                            backgroundColor: ShodashaTheme.bg,
                            side: BorderSide(
                              color: _sameDay(day, selectedDay)
                                  ? ShodashaTheme.teal
                                  : ShodashaTheme.border,
                            ),
                            labelStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _sameDay(day, selectedDay)
                                  ? ShodashaTheme.tealDeep
                                  : ShodashaTheme.ink,
                            ),
                            onSelected: (_) => setSheet(() {
                              selectedDay = day;
                              selected = null;
                            }),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    '${_dayLabel(selectedDay)} · choose a 30-min slot',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final slot in slots)
                        ChoiceChip(
                          label: Text(slot.label),
                          selected: selected == slot,
                          showCheckmark: false,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          selectedColor: ShodashaTheme.tealTint,
                          backgroundColor: ShodashaTheme.bg,
                          side: BorderSide(
                            color: selected == slot
                                ? ShodashaTheme.teal
                                : ShodashaTheme.border,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected == slot
                                ? ShodashaTheme.tealDeep
                                : ShodashaTheme.ink,
                          ),
                          onSelected: (_) => setSheet(() => selected = slot),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked == null || !mounted) return;
    final done = await widget.controller.reschedule(order.id, picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? ordersStringsHi['rescheduled']!
              : ordersStringsHi['rescheduleFailed']!,
        ),
      ),
    );
  }

  Future<void> _openWhatsApp(Order order) async {
    final opened = await widget.controller.openWhatsApp('order ${order.id}');
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ordersStringsHi['whatsappFail']!)));
    }
  }

  Future<void> _openBill(Order order) async {
    if (_pushingBill) return;
    _pushingBill = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => BillScreen(order: order)),
      );
    } finally {
      _pushingBill = false;
    }
  }

  Future<void> _callRider(Order order) async {
    final phone = order.riderPhone;
    if (phone == null || phone.isEmpty) return;
    final opened = await widget.controller.openDialer(phone);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ordersStringsHi['callFail']!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(
        backgroundColor: ShodashaTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: ShodashaTheme.border)),
        leadingWidth: 56,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded, color: ShodashaTheme.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '#${widget.orderId}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: ShodashaTheme.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final order = widget.controller.findById(widget.orderId);
            // Detail missing: spinner while the list is still loading,
            // otherwise message + retry instead of a bare line. Refresh
            // re-reads the order.
            if (order == null) {
              if (_detailLoading ||
                  widget.controller.status == OrdersListStatus.loading) {
                // Phase 9 §9.1: tracker-shaped skeleton (was a bare
                // spinner) — same blueTint rhythm as the orders list.
                return const _TrackingSkeleton();
              }
              return AppStateView.error(
                isNetwork: widget.controller.detailOffline,
                title: widget.controller.detailOffline
                    ? null
                    : 'Could not load this order',
                message: widget.controller.detailServerError
                    ? 'Server problem — try again in a moment.'
                    : null,
                onRetry: _retryDetail,
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeaderCard(order: order),
                  if (widget.controller.detailFailed) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _StaleBanner(
                      offline: widget.controller.detailOffline,
                      server: widget.controller.detailServerError,
                      busy: _detailLoading,
                      onRetry: _retryDetail,
                    ),
                  ],
                  ..._deliveryCodeSection(order),
                  const SizedBox(height: AppSpacing.md),
                  if (order.state == OrderState.cancelled)
                    _FlatBanner(text: ordersStringsHi['cancelledBanner']!)
                  else if (order.state == OrderState.failed)
                    _FlatBanner(
                      text: ordersStringsHi['failedBanner']!,
                      isError: true,
                    )
                  else if (order.state == OrderState.rejected)
                    _FlatBanner(text: ordersStringsHi['rejectedBanner']!)
                  else if (trackerStep(order.state) >= 0)
                    _FourStepTracker(step: trackerStep(order.state))
                  else
                    _FlatBanner(text: ordersStringsHi['deliveredBanner']!),
                  const SizedBox(height: AppSpacing.md),
                  _WindowCard(order: order),
                  if (order.stopsAhead != null &&
                      (order.state == OrderState.dispatched ||
                          order.state == OrderState.assigned)) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _LiveStopsAheadBanner(
                      stopsAhead: order.stopsAhead!,
                      order: order,
                    ),
                  ],
                  if (order.riderName != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _RiderCard(order: order, onCall: () => _callRider(order)),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  _BillRow(order: order, onOpen: () => _openBill(order)),
                  const SizedBox(height: AppSpacing.md),
                  _ActionsFor(
                    order: order,
                    busy: widget.controller.actionBusy,
                    onCancel: () => _confirmCancel(order),
                    onReschedule: () => _confirmReschedule(order),
                    onWhatsApp: () => _openWhatsApp(order),
                    onRate: () => showRatingSheet(
                      context,
                      widget.controller,
                      order,
                      onSupport: widget.onSupport,
                    ),
                    onCall: () => _callRider(order),
                    onSupport: widget.onSupport,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Status updates automatically every '
                    '${widget.controller.pollSeconds}s',
                    style: const TextStyle(
                      fontSize: 12,
                      color: ShodashaTheme.muted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// The delivery code is the single secret shown only on tracking. `none`
  /// hides the whole chip; every other state gets explicit copy.
  List<Widget> _deliveryCodeSection(Order order) {
    var state = order.deliveryCodeStateAt(_now);
    if (state == 'active' &&
        (order.deliveryOtp == null || order.deliveryOtp!.isEmpty)) {
      state = 'unavailable';
    }
    if (state == 'none') return const [];

    final locallyExpired =
        state == 'expired' && order.deliveryCodeState == 'active';
    final needsNewCode = const {
      'expired',
      'locked',
      'unavailable',
    }.contains(state);
    // The server gate is authoritative; a local 24h rollover also offers the
    // action so the user is never stuck waiting for a poll.
    final canReissue =
        order.state == OrderState.dispatched &&
        needsNewCode &&
        (order.deliveryCodeReissueAvailable || locallyExpired);

    return [
      const SizedBox(height: 12),
      _DeliveryCodeCard(
        state: state,
        code: order.deliveryOtp,
        expiresAt: order.deliveryCodeExpiresAt,
        now: _now,
        busy: widget.controller.reissueBusy,
        showReissue: canReissue,
        error: _reissueError,
        onReissue: _reissueCode,
      ),
    ];
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.order});
  final Order order;

  (StatusPillTone, IconData) get _tone => switch (order.state) {
    OrderState.delivered => (
      StatusPillTone.success,
      Icons.check_circle_outline,
    ),
    OrderState.cancelled => (StatusPillTone.neutral, Icons.block_outlined),
    OrderState.rejected ||
    OrderState.failed => (StatusPillTone.danger, Icons.error_outline),
    OrderState.dispatched || OrderState.assigned => (
      StatusPillTone.warning,
      Icons.local_shipping_outlined,
    ),
    _ => (StatusPillTone.info, Icons.schedule_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = _tone;
    final title = order.itemSummary.isEmpty
        ? 'Order #${order.id}'
        : order.itemSummary;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: ShodashaTheme.ink,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusPill(
                label: orderStateLabel(order.state),
                tone: tone,
                icon: icon,
              ),
            ],
          ),
          if (order.addressLabel.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: ShodashaTheme.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.addressLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: ShodashaTheme.muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Divider(height: 1, color: ShodashaTheme.border),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatRupees(order.totalPaise),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: ShodashaTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total bill',
                      style: const TextStyle(
                        fontSize: 12,
                        color: ShodashaTheme.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      order.paymentLabel,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: order.isPaid
                            ? ShodashaTheme.successDark
                            : ShodashaTheme.muted,
                      ),
                    ),
                    if (order.refundPending) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${ordersStringsHi['refundPending']!} • '
                        '${formatRupees(order.refundAmountPaise)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: ShodashaTheme.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Custom 4-step tracker: solid dots + solid connectors (flat, no shadows).
class FourStepTracker extends StatelessWidget {
  const FourStepTracker({super.key, required this.step});
  final int step;

  @override
  Widget build(BuildContext context) => _FourStepTracker(step: step);
}

class _FourStepTracker extends StatelessWidget {
  const _FourStepTracker({required this.step});
  final int step;

  static const _labels = ['Confirmed', 'Packed', 'On the way', 'Delivered'];

  @override
  Widget build(BuildContext context) {
    // a11y-2: progress announced as one node (step X of 4 + label).
    return Semantics(
      container: true,
      label: 'Order progress: step ${step + 1} of 4, ${_labels[step]}',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ShodashaTheme.surface,
          border: Border.all(color: ShodashaTheme.border),
          borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
        ),
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  _Dot(filled: i <= step),
                  if (i < 3) _Connector(filled: i < step),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Text(
                      _labels[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: i == step
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: i <= step
                            ? ShodashaTheme.teal
                            : ShodashaTheme.muted,
                      ),
                      textAlign: i == 0
                          ? TextAlign.start
                          : i == 3
                          ? TextAlign.end
                          : TextAlign.center,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.filled});
  final bool filled;

  @override
  Widget build(BuildContext context) {
    // Phase 9 §9.1: the fill change pops (scale) + the check fades in —
    // 200ms, transform + opacity only. Static when reduced motion is on
    // (the color still flips instantly, so state never depends on motion).
    // Active flow color is the brand teal (locked palette v2).
    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: filled ? ShodashaTheme.teal : ShodashaTheme.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: filled ? ShodashaTheme.teal : ShodashaTheme.border,
            width: 2,
          ),
        ),
        child: filled
            ? const Icon(Icons.check, size: 12, color: ShodashaTheme.surface)
            : null,
      );
    }
    return AnimatedScale(
      scale: filled ? 1.0 : 0.8,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: filled ? ShodashaTheme.teal : ShodashaTheme.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: filled ? ShodashaTheme.teal : ShodashaTheme.border,
            width: 2,
          ),
        ),
        child: AnimatedOpacity(
          opacity: filled ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: const Icon(
            Icons.check,
            size: 12,
            color: ShodashaTheme.surface,
          ),
        ),
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.filled});
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 3,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: filled ? ShodashaTheme.teal : ShodashaTheme.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _TrackingSkeleton extends StatelessWidget {
  const _TrackingSkeleton();

  @override
  Widget build(BuildContext context) {
    // Mirrors the loaded layout (header card + tracker card + bill card)
    // so content replaces boxes 1:1 with no layout pop.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _skelBox(64),
          const SizedBox(height: 16),
          _skelBox(132),
          const SizedBox(height: 16),
          _skelBox(88),
        ],
      ),
    );
  }

  static Widget _skelBox(double height) => Container(
    height: height,
    decoration: BoxDecoration(
      color: ShodashaTheme.tealTint,
      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
    ),
  );
}

class _WindowCard extends StatelessWidget {
  const _WindowCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    final s = order.windowStart;
    final e = order.windowEnd ?? s.add(const Duration(minutes: 30));
    return Container(
      // Donor schedule row — brand tint card, teal accent on the cue,
      // 900-weight time as the value line.
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShodashaTheme.tealTint,
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 20, color: ShodashaTheme.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ordersStringsHi['windowLabel']!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.teal,
                  ),
                ),
                // F10: date rides with the time — a bare HH:MM hides
                // which day (kal/parson confusion at midnight).
                Text(
                  '${two(s.day)}/${two(s.month)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ShodashaTheme.ink,
                  ),
                ),
                Text(
                  '${two(s.hour)}:${two(s.minute)} - '
                  '${two(e.hour)}:${two(e.minute)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    color: ShodashaTheme.ink,
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

class _LiveStopsAheadBanner extends StatelessWidget {
  const _LiveStopsAheadBanner({required this.stopsAhead, required this.order});

  final int stopsAhead;
  final Order order;

  @override
  Widget build(BuildContext context) {
    final isNext = stopsAhead == 0;
    // Single brand treatment (donor status-banner grammar, token
    // palette only): teal for both live states, depth from the icon chip —
    // no out-of-token colors.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShodashaTheme.tealTint,
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
        border: Border.all(
          color: isNext
              ? ShodashaTheme.teal.withValues(alpha: 0.45)
              : ShodashaTheme.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isNext ? ShodashaTheme.teal : ShodashaTheme.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isNext ? Icons.local_shipping : Icons.route,
              color: isNext ? ShodashaTheme.surface : ShodashaTheme.teal,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isNext
                      ? 'Your stop is next!'
                      : 'Driver is $stopsAhead stops away',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ShodashaTheme.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isNext
                      ? 'The driver is arriving at your address. Please keep your empty jar ready.'
                      : 'Estimated time: about ${stopsAhead * 10}–${stopsAhead * 15} minutes. Keep your empty jar outside.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: ShodashaTheme.ink,
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

class _RiderCard extends StatelessWidget {
  const _RiderCard({required this.order, required this.onCall});
  final Order order;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Row(
        children: [
          // Donor tile grammar: tinted icon chip + label/name stack.
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: ShodashaTheme.tealTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.delivery_dining_outlined,
              size: 20,
              color: ShodashaTheme.teal,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ordersStringsHi['riderLabel']!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: ShodashaTheme.muted,
                  ),
                ),
                Text(
                  order.riderName ?? '',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
              ],
            ),
          ),
          if (order.riderPhone != null)
            SizedBox(
              height: ShodashaTheme.minTarget,
              child: OutlinedButton(
                onPressed: onCall,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ShodashaTheme.teal,
                  side: const BorderSide(color: ShodashaTheme.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                  ),
                ),
                child: Text(ordersStringsHi['callRider']!),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeliveryCodeCard extends StatelessWidget {
  const _DeliveryCodeCard({
    required this.state,
    required this.code,
    required this.expiresAt,
    required this.now,
    required this.busy,
    required this.showReissue,
    required this.error,
    required this.onReissue,
  });

  final String state;
  final String? code;
  final DateTime? expiresAt;
  final DateTime now;
  final bool busy;
  final bool showReissue;
  final String? error;
  final VoidCallback onReissue;

  static const _title = 'Delivery code';

  @override
  Widget build(BuildContext context) {
    final active = state == 'active';
    final icon = switch (state) {
      'expired' => Icons.lock_clock_outlined,
      'locked' => Icons.lock_outline,
      'unavailable' => Icons.help_outline,
      'used' => Icons.check_circle_outline,
      _ => Icons.key_outlined,
    };
    final iconColor = switch (state) {
      'locked' => ShodashaTheme.danger,
      'used' => ShodashaTheme.success,
      'expired' => ShodashaTheme.muted,
      _ => ShodashaTheme.teal,
    };
    final headline = switch (state) {
      'expired' => 'Code expired',
      'locked' => 'Too many wrong attempts',
      'unavailable' => 'Code unavailable',
      'used' => 'Delivery complete — code used.',
      _ => _title,
    };
    final support = switch (state) {
      'expired' => 'This code can no longer be used. Get a new one.',
      'locked' => 'For your safety this code is locked. Get a new one.',
      'unavailable' =>
        'We could not find a code for this delivery. Get a new one.',
      'used' => 'The rider completed this delivery with your code.',
      _ => null,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(
          color: state == 'locked'
              ? ShodashaTheme.danger.withValues(alpha: 0.35)
              : ShodashaTheme.border,
        ),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: active ? ShodashaTheme.tealTint : ShodashaTheme.bg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        fontSize: active ? 11 : 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: active ? 0.5 : 0,
                        color: active ? ShodashaTheme.muted : ShodashaTheme.ink,
                      ),
                    ),
                    if (support != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        support,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: ShodashaTheme.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (active && code != null && code!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: ShodashaTheme.bg,
                border: Border.all(color: ShodashaTheme.border),
                borderRadius: BorderRadius.circular(ShodashaTheme.radius / 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    label:
                        'Delivery code ${code!.split('').join(' ')}. '
                        'Tell this code to the rider at delivery.',
                    child: ExcludeSemantics(
                      child: Text(
                        code!,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: ShodashaTheme.teal,
                          letterSpacing: 6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _secondary(expiresAt, now),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ShodashaTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (showReissue) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: ShodashaTheme.minTarget,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onReissue,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ShodashaTheme.teal,
                  side: const BorderSide(color: ShodashaTheme.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                  ),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ShodashaTheme.teal,
                        ),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(
                  busy ? 'Getting a new code…' : 'Get new code',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 16,
                  color: ShodashaTheme.danger,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: ShodashaTheme.danger,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Minute precision is enough for a 24h code; the screen recomputes on
  /// resume and on the 30s rollover tick.
  static String _secondary(DateTime? expiresAt, DateTime now) {
    if (expiresAt == null) return 'Rider will ask at delivery.';
    final left = expiresAt.difference(now);
    if (left.isNegative) return 'Expiring now…';
    if (left.inHours >= 1) {
      return 'Expires in ${left.inHours}h ${left.inMinutes % 60}m';
    }
    if (left.inMinutes >= 1) return 'Expires in ${left.inMinutes}m';
    return 'Expires in under a minute';
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.order, required this.onOpen});
  final Order order;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${ordersStringsHi['viewBill']!} • '
                  '${formatRupees(order.totalPaise)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: ShodashaTheme.muted,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            order.paymentLabel,
            style: TextStyle(
              fontSize: 12,
              color: order.isPaid
                  ? ShodashaTheme.successDark
                  : ShodashaTheme.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (order.paymentsPaise > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Paid ${formatRupees(order.paymentsPaise)} to the vendor — '
              'confirm in the bill',
              style: const TextStyle(
                fontSize: 12,
                color: ShodashaTheme.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({
    required this.offline,
    required this.server,
    required this.busy,
    required this.onRetry,
  });

  final bool offline;
  final bool server;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = offline
        ? 'No internet — showing the last update.'
        : server
        ? 'Server problem — showing the last update.'
        : 'Could not refresh — showing the last update.';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: ShodashaTheme.bg,
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
        border: Border.all(color: ShodashaTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, size: 18, color: ShodashaTheme.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: ShodashaTheme.muted,
              ),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _FlatBanner extends StatelessWidget {
  const _FlatBanner({required this.text, this.isError = false});
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    // Tokens only — neutral ground + red text/border for errors
    // (always paired with copy, never color-alone), brand tint otherwise.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShodashaTheme.bg,
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
        border: Border.all(
          color: isError
              ? ShodashaTheme.danger.withValues(alpha: 0.4)
              : ShodashaTheme.border,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isError ? ShodashaTheme.danger : ShodashaTheme.teal,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Visibility-matrix actions (single place so list + detail stay consistent).
class _ActionsFor extends StatelessWidget {
  const _ActionsFor({
    required this.order,
    required this.busy,
    required this.onCancel,
    required this.onReschedule,
    required this.onWhatsApp,
    required this.onRate,
    required this.onCall,
    this.onSupport,
  });

  final Order order;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;
  final VoidCallback onWhatsApp;
  final VoidCallback onRate;
  final VoidCallback onCall;
  final VoidCallback? onSupport;

  @override
  Widget build(BuildContext context) {
    if (order.canCancel || order.canReschedule) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 380;
          final cancel = order.canCancel
              ? AppButton(
                  label: 'Cancel',
                  kind: AppButtonKind.secondary,
                  onPressed: busy ? null : onCancel,
                )
              : null;
          final reschedule = order.canReschedule
              ? AppButton(
                  label: 'Reschedule',
                  onPressed: busy ? null : onReschedule,
                )
              : null;
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?cancel,
                if (cancel != null && reschedule != null)
                  const SizedBox(height: AppSpacing.sm),
                ?reschedule,
              ],
            );
          }
          return Row(
            children: [
              if (cancel != null) Expanded(child: cancel),
              if (cancel != null && reschedule != null)
                const SizedBox(width: AppSpacing.sm),
              if (reschedule != null) Expanded(child: reschedule),
            ],
          );
        },
      );
    }
    if (order.showWhatsAppOnly) {
      return AppButton(
        label: ordersStringsHi['whatsappHelp']!,
        icon: Icons.chat_outlined,
        onPressed: onWhatsApp,
      );
    }
    if (order.showHelpRow) {
      final hasPhone = (order.riderPhone ?? '').trim().isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final call = AppButton(
                label: ordersStringsHi['callRider']!,
                kind: AppButtonKind.secondary,
                icon: Icons.call_outlined,
                onPressed: hasPhone ? onCall : null,
              );
              final whatsapp = AppButton(
                label: 'WhatsApp',
                kind: AppButtonKind.secondary,
                icon: Icons.chat_outlined,
                onPressed: onWhatsApp,
              );
              if (constraints.maxWidth < 380) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    call,
                    const SizedBox(height: AppSpacing.sm),
                    whatsapp,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: call),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: whatsapp),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          if (order.rated)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: ShodashaTheme.greenSoft,
                borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                border: Border.all(color: ShodashaTheme.greenBorder),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 20,
                    color: ShodashaTheme.successDark,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      order.stars == null
                          ? 'Thanks for rating this delivery.'
                          : 'You rated this delivery ${order.stars}/5.',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ShodashaTheme.successDark,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            AppButton(
              label: ordersStringsHi['rateTitle']!,
              icon: Icons.star_outline_rounded,
              onPressed: busy ? null : onRate,
            ),
        ],
      );
    }
    if (order.state == OrderState.rejected ||
        order.state == OrderState.failed ||
        order.state == OrderState.cancelled) {
      final support = onSupport ?? onWhatsApp;
      return AppButton(
        label: order.state == OrderState.cancelled
            ? 'Need help with this order?'
            : 'Talk to support',
        kind: AppButtonKind.secondary,
        icon: Icons.support_agent_outlined,
        onPressed: support,
      );
    }
    return const SizedBox.shrink();
  }
}
