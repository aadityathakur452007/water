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
import 'bill_screen.dart';
import 'orders_controller.dart';
import 'rating_sheet.dart';

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
  RescheduleSlot? _slot;
  bool _ratingShown = false;
  bool _detailLoading = false;
  DateTime _now = DateTime.now();
  Timer? _codeTimer;
  String? _reissueError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detailLoading = widget.controller.findById(widget.orderId) == null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.refreshOrder(widget.orderId);
      if (mounted && _detailLoading) {
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
    if (state != AppLifecycleState.resumed) return;
    setState(() => _now = DateTime.now());
    _syncCodeTimer();
    widget.controller.refreshOrder(widget.orderId);
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
    final slots = nextServiceSlots();
    _slot = slots.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ShodashaTheme.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        ),
        title: Text(
          ordersStringsHi['rescheduleTitle']!,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: ShodashaTheme.ink,
          ),
        ),
        content: StatefulBuilder(
          builder: (ctx, setD) => DropdownButtonFormField<RescheduleSlot>(
            initialValue: _slot,
            decoration: InputDecoration(
              labelText: ordersStringsHi['windowLabel'],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ShodashaTheme.radius),
              ),
            ),
            items: [
              for (final s in slots)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (v) {
              if (v != null) setD(() => _slot = v);
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
            child: Text(ordersStringsHi['rescheduleConfirm']!),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || _slot == null) return;
    final done = await widget.controller.reschedule(order.id, _slot!.start);
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
        backgroundColor: ShodashaTheme.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: ShodashaTheme.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '#${widget.orderId}',
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
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ordersStringsHi['errorTitle']!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: ShodashaTheme.muted),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _retryDetail,
                        child: Text(ordersStringsHi['retry']!),
                      ),
                    ],
                  ),
                ),
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeaderCard(order: order),
                  if (widget.controller.detailFailed) ...[
                    const SizedBox(height: 12),
                    _StaleBanner(
                      offline: widget.controller.detailOffline,
                      server: widget.controller.detailServerError,
                      busy: _detailLoading,
                      onRetry: _retryDetail,
                    ),
                  ],
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 16),
                  _WindowCard(order: order),
                  if (order.stopsAhead != null &&
                      (order.state == OrderState.dispatched ||
                          order.state == OrderState.assigned)) ...[
                    const SizedBox(height: 12),
                    _LiveStopsAheadBanner(
                      stopsAhead: order.stopsAhead!,
                      order: order,
                    ),
                  ],
                  if (order.riderName != null) ...[
                    const SizedBox(height: 12),
                    _RiderCard(order: order, onCall: () => _callRider(order)),
                  ],
                  ..._deliveryCodeSection(order),
                  const SizedBox(height: 12),
                  _BillRow(
                    order: order,
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BillScreen(order: order),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${ordersStringsHi['autoRefresh']}: '
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

  @override
  Widget build(BuildContext context) {
    return Container(
      // Donor card grammar: white on the slate ground, hairline border.
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.itemSummary.isEmpty
                      ? '#${order.id}'
                      : order.itemSummary,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: ShodashaTheme.ink,
                  ),
                ),
                if (order.addressLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    order.addressLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      color: ShodashaTheme.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatRupees(order.totalPaise),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: ShodashaTheme.ink,
                ),
              ),
              // 015: payment mode + paid state badge (UPI/COD visibility).
              // Money-state cue: token success when paid, muted when due.
              Text(
                order.isPaid
                    ? '${order.paymentMode.toUpperCase()} • Paid'
                    : '${order.paymentMode.toUpperCase()} • ${formatRupees(order.totalPaise - order.paymentsPaise)} due',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: order.isPaid
                      ? ShodashaTheme.success
                      : ShodashaTheme.muted,
                ),
              ),
              if (order.refundPending)
                Text(
                  ordersStringsHi['refundPending']!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: ShodashaTheme.muted,
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

  static const _title = 'Delivery code / डिलीवरी कोड';

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
    // 015: tappable bill row (was dead Container) + vendor-collect note.
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ShodashaTheme.surface,
          border: Border.all(color: ShodashaTheme.border),
          borderRadius: BorderRadius.circular(ShodashaTheme.radiusLg),
        ),
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
                const Icon(Icons.chevron_right, color: ShodashaTheme.muted),
              ],
            ),
            if (order.paymentsPaise > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Paid ${formatRupees(order.paymentsPaise)} to the vendor — confirm in the bill',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ShodashaTheme.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
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
  });

  final Order order;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;
  final VoidCallback onWhatsApp;
  final VoidCallback onRate;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    if (order.canCancel || order.canReschedule) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: ShodashaTheme.minTarget,
              child: OutlinedButton(
                onPressed: busy ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ShodashaTheme.ink,
                  side: const BorderSide(color: ShodashaTheme.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                  ),
                ),
                child: Text(ordersStringsHi['cancelTitle']!),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: ShodashaTheme.minTarget,
              child: ElevatedButton(
                onPressed: busy ? null : onReschedule,
                style: ElevatedButton.styleFrom(
                  // Schedule action → structure teal (not a money CTA).
                  backgroundColor: ShodashaTheme.teal,
                  foregroundColor: ShodashaTheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                  ),
                ),
                child: Text(ordersStringsHi['rescheduleTitle']!),
              ),
            ),
          ),
        ],
      );
    }
    if (order.showWhatsAppOnly) {
      return SizedBox(
        height: ShodashaTheme.minTarget,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onWhatsApp,
          style: ElevatedButton.styleFrom(
            backgroundColor: ShodashaTheme.teal,
            foregroundColor: ShodashaTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
          ),
          child: Text(ordersStringsHi['whatsappHelp']!),
        ),
      );
    }
    if (order.showHelpRow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ShodashaTheme.surface,
              border: Border.all(color: ShodashaTheme.border),
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: onCall,
                    style: TextButton.styleFrom(
                      foregroundColor: ShodashaTheme.teal,
                      minimumSize: const Size(48, ShodashaTheme.minTarget),
                    ),
                    child: Text(ordersStringsHi['callRider']!),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: onWhatsApp,
                    style: TextButton.styleFrom(
                      foregroundColor: ShodashaTheme.teal,
                      minimumSize: const Size(48, ShodashaTheme.minTarget),
                    ),
                    child: Text(ordersStringsHi['whatsappHelp']!),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: ShodashaTheme.minTarget,
            child: ElevatedButton(
              onPressed: order.canRate ? onRate : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: ShodashaTheme.teal,
                foregroundColor: ShodashaTheme.surface,
                disabledBackgroundColor: ShodashaTheme.teal.withValues(
                  alpha: 0.3,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                ),
              ),
              child: Text(ordersStringsHi['rateTitle']!),
            ),
          ),
        ],
      );
    }
    if (order.state == OrderState.failed) {
      return SizedBox(
        height: ShodashaTheme.minTarget,
        child: OutlinedButton.icon(
          onPressed: onWhatsApp,
          icon: const Icon(Icons.support_agent, color: ShodashaTheme.teal),
          style: OutlinedButton.styleFrom(
            foregroundColor: ShodashaTheme.teal,
            side: const BorderSide(color: ShodashaTheme.teal),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
          ),
          label: const Text('Talk to support / WhatsApp'),
        ),
      );
    }
    // cancelled (and terminal rejected): no actions.
    return const SizedBox.shrink();
  }
}
