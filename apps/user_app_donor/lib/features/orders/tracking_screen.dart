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
import '../../core/utils/date_utils.dart';
import 'bill_screen.dart';
import 'orders_controller.dart';
import 'rating_sheet.dart';

part 'widgets/tracking_cards.dart';

String _dayLabel(DateTime d) {
  return '${kShortWeekdays[d.weekday - 1]}, ${d.day} ${kShortMonths[d.month - 1]}';
}

String _shortDayLabel(DateTime d) {
  return '${kShortWeekdays[d.weekday - 1]} ${d.day}';
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
          builder: (ctx, setD) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (order.state == OrderState.assigned ||
                  order.state == OrderState.dispatched) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: ShodashaTheme.solarTint,
                    borderRadius:
                        BorderRadius.circular(ShodashaTheme.radiusSm),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: ShodashaTheme.warning),
                      SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'A delivery partner is assigned. Cancelling will alert the rider and vendor not to deliver.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ShodashaTheme.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              DropdownButtonFormField<CancelReason>(
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
            ],
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
    if (done) {
      widget.controller.stopTracking();
      Navigator.of(context).pop(true);
      return;
    }
    final errorMsg = widget.controller.cancelErrorMessage ??
        ordersStrings['cancelFailed']!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMsg),
        backgroundColor: ShodashaTheme.danger,
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
        final initialSlots = serviceSlotsForDay(selectedDay);
        RescheduleSlot? selected =
            initialSlots.isNotEmpty ? initialSlots.first : null;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final slots = serviceSlotsForDay(selectedDay);
            selected ??= slots.isNotEmpty ? slots.first : null;
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
                              final s = serviceSlotsForDay(day);
                              selected = s.isNotEmpty ? s.first : null;
                            }),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    '${_dayLabel(selectedDay)} · Delivery Window',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: ShodashaTheme.tealTint,
                      borderRadius:
                          BorderRadius.circular(ShodashaTheme.radiusSm),
                      border: Border.all(color: ShodashaTheme.teal),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.wb_sunny_outlined,
                          color: ShodashaTheme.teal,
                          size: 20,
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Morning Delivery (7:00 AM – 12:00 PM)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: ShodashaTheme.tealDeep,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Delivered during the morning neighborhood route',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: ShodashaTheme.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                      text: (order.failureReason != null &&
                              order.failureReason!.isNotEmpty)
                          ? 'Delivery could not be completed: ${formatFailureReason(order.failureReason)}'
                          : ordersStringsHi['failedBanner']!,
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
                  if (order.riderName != null &&
                      order.state != OrderState.failed &&
                      order.state != OrderState.cancelled &&
                      order.state != OrderState.rejected) ...[
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

