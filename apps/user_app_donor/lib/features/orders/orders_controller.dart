// S5 — Orders state for the donor-based customer app (032 replacement).
//
// Ported VERBATIM from apps/user_app_legacy_flutter (F4 controller): same
// state enum, mapper, repository seam, paging, polling backoff, visibility
// matrix and copy. Only the transport import is re-pointed at the ported
// core (single ApiClient, Bearer + X-Device-Id + Idempotency-Key).
//
// Backend contract: Feature_docs/backend/api-contract.md §4.4
// (POST /orders idempotent + quote-lock, GET /orders cursor paging,
// GET /orders/{id} + /tracking, POST cancel pre-dispatch only with
// {reason} + Idempotency-Key, POST reschedule pre-dispatch only with
// {window_start}, POST rating once per delivered order).
//
// States.md covered: initial/loading/loaded/error, offline (loaded rows stay
// visible), refreshing, search/no-results, action pending/busy, retry.
//
// Wiring notes: tel:/wa.me launch via url_launcher; a false result is
// surfaced as a SnackBar by the screen (never a dead button).
// - Money is integer paise everywhere; [formatRupees] formats only for
//   display (2dp only when needed). No money is ever computed here.

// ignore_for_file: prefer_initializing_formals
// WHY: public ctor param `repo:` is the API (tests + shell wiring construct
// this); private initializing formals are unusable from other libraries —
// same pattern as features/auth/auth_controller.dart.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';

part 'order_models.dart';
part 'orders_repositories.dart';

/// English copy for the orders feature (v1, ADR-120). Keys stay stable for a
/// later Hinglish l10n pass.
const Map<String, String> ordersStrings = {
  'ordersTitle': 'My orders',
  'searchHint': 'Search order ID or address',
  'emptyTitle': 'No orders yet',
  'emptyHint': 'Place your first order — delivery tomorrow morning',
  'noResultsTitle': 'No matching orders',
  'noResultsHint': 'Try a different search',
  'errorTitle': 'Could not load orders',
  'offlineTitle': 'Offline — showing older orders',
  'retry': 'Try again',
  'loadMore': 'Load more orders',
  'loadMoreFailed': 'Could not load more orders',
  'cancelTitle': 'Cancel this order?',
  'cancelConfirm': 'Yes, cancel it',
  'cancelKeep': 'Keep it',
  'cancelFailed': 'Could not cancel this order — try again',
  'cancelReasonLabel': 'Choose a cancellation reason',
  'rescheduleTitle': 'Change delivery time',
  'rescheduleConfirm': 'Confirm new time',
  'rescheduled': 'Delivery time updated',
  'rescheduleFailed': 'Could not change the delivery time — try again',
  'whatsappHelp': 'Help on WhatsApp',
  'whatsappFail': 'Could not open WhatsApp — try between 8AM–8PM',
  'callFail': 'Could not open the dialer',
  'callRider': 'Call the rider',
  'deliveredBanner': 'Order delivered',
  'cancelledBanner': 'Order cancelled',
  'failedBanner': 'Delivery failed — contact support',
  'rejectedBanner': 'Order rejected — refund on the way',
  'refundPending': 'Refund pending — amount frozen, will not change',
  'duesNote': 'Remaining amount will be added to your next bill',
  'rateTitle': 'How was the delivery?',
  'rateSubmit': 'Submit rating',
  'rateThanks': 'Thanks! Your rating was received',
  'rateAgain': 'A rating can be submitted only once',
  'rateFailed': 'Could not submit your rating — try again',
  'complaintShortcut': 'Something wrong? File a complaint',
  'viewBill': 'View bill',
  'autoRefresh': 'Auto-refresh',
  'windowLabel': 'Delivery window',
  'riderLabel': 'Rider',
};

/// Compatibility alias for ordersStrings (DEF-16).
const Map<String, String> ordersStringsHi = ordersStrings;

/// Canonical order lifecycle (contract §4.4 + §9 state machine).
/// Payment is a separate field, never a state.
enum OrdersListStatus { initial, loading, loaded, error }

/// Rating outcome — a 409/“already rated” is not a transport failure and must
/// not close the sheet with retry copy meant for network errors.
enum RateResult { success, alreadyRated, failed }

/// Reissue outcome. Failures stay inline on the delivery-code card; a 429
/// carries the server wait so the UI can show it without inventing a timer.
@immutable
class DeliveryCodeReissueResult {
  const DeliveryCodeReissueResult({
    required this.ok,
    this.message,
    this.retryAfterSeconds = 0,
  });

  const DeliveryCodeReissueResult.success()
    : ok = true,
      message = null,
      retryAfterSeconds = 0;

  const DeliveryCodeReissueResult.failed(
    String this.message, {
    this.retryAfterSeconds = 0,
  }) : ok = false;

  final bool ok;
  final String? message;
  final int retryAfterSeconds;
}

/// Orders lifecycle: list(search client-side) → tracking(poll) → bill(frozen)
/// → rating(once). Covers States.md data/error/network/search/action states.
class OrdersController extends ChangeNotifier {
  OrdersController({required OrdersRepository repo}) : _repo = repo;

  final OrdersRepository _repo;

  OrdersListStatus _status = OrdersListStatus.initial;
  final List<Order> _all = [];
  String _query = '';
  String? _errorMessage;
  bool _isOffline = false;
  bool _isServerError = false;
  bool _loadMoreFailed = false;
  String? _loadMoreError;
  bool _loadingMore = false;
  String? _cursor;
  bool _hasMore = false;
  bool _actionBusy = false;
  bool _reissueBusy = false;
  bool _detailFailed = false;
  bool _detailOffline = false;
  bool _detailServerError = false;

  Timer? _pollTimer;
  String? _trackingId;
  bool _trackingPaused = false;
  int _pollSeconds = pollBaseSeconds;
  bool _disposed = false;

  /// User boundary: bumped by [reset]; async completions from the previous
  /// account are discarded instead of repopulating the list.
  int _generation = 0;

  /// Rating auto-popup fires once per delivered order view (approved answer 5).
  final Set<String> _ratingPrompted = {};

  /// Poll cadence: 60s base, exponential backoff, 300s max.
  static const int pollBaseSeconds = 60;
  static const int pollMaxSeconds = 300;

  OrdersListStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isOffline => _isOffline;
  bool get isServerError => _isServerError;
  bool get loadMoreFailed => _loadMoreFailed;
  String? get loadMoreError => _loadMoreError;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  bool get actionBusy => _actionBusy;
  bool get reissueBusy => _reissueBusy;
  bool get detailFailed => _detailFailed;
  bool get detailOffline => _detailOffline;
  bool get detailServerError => _detailServerError;
  int get pollSeconds => _pollSeconds;
  String get query => _query;
  int get totalCount => _all.length;
  List<Order> get allOrders => List.unmodifiable(_all);

  /// Client-side filter over id + address + item summary (no server `q`).
  List<Order> get filteredOrders {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return List.unmodifiable(_all);
    return List.unmodifiable(
      _all.where(
        (o) =>
            o.id.toLowerCase().contains(q) ||
            o.addressLabel.toLowerCase().contains(q) ||
            o.itemSummary.toLowerCase().contains(q),
      ),
    );
  }

  Order? findById(String id) {
    for (final o in _all) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Most recent order whose SKU mix is known -- used for 1-tap reorder.
  /// Returns null when list is empty or all rows are legacy (canReorder==false).
  Order? get reorderCandidate {
    for (final o in _all) {
      if (o.canReorder) return o;
    }
    return null;
  }

  void setQuery(String q) {
    _query = q;
    _notify();
  }

  /// First load (skeleton in the screen while [_status] is loading).
  /// User boundary: clears every row/flag and invalidates in-flight loads so
  /// a response landing after logout can never repopulate the list.
  void reset() {
    _generation++;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollSeconds = pollBaseSeconds;
    _all.clear();
    _query = '';
    _errorMessage = null;
    _isOffline = false;
    _isServerError = false;
    _cursor = null;
    _hasMore = false;
    _loadMoreFailed = false;
    _loadingMore = false;
    _actionBusy = false;
    _reissueBusy = false;
    _detailFailed = false;
    _detailOffline = false;
    _detailServerError = false;
    _status = OrdersListStatus.initial;
    _ratingPrompted.clear();
    _notify();
  }

  Future<void> load({bool silent = false}) async {
    if (_status == OrdersListStatus.loading) return;
    if (!silent) {
      _status = OrdersListStatus.loading;
      _errorMessage = null;
      _loadMoreFailed = false;
      _loadMoreError = null;
      _notify();
    }
    final gen = _generation;
    try {
      final page = await _repo.fetchOrders();
      if (gen != _generation) return; // reset mid-flight (logout/user switch)
      _all
        ..clear()
        ..addAll(page.orders);
      _cursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
      _status = OrdersListStatus.loaded;
      _isOffline = false;
      _isServerError = false;
      _onPollSuccess();
    } catch (e) {
      if (gen != _generation) return;
      if (!silent) {
        _status = _all.isEmpty ? OrdersListStatus.error : OrdersListStatus.loaded;
        _errorMessage = e is ApiException && e.isOffline
            ? 'No internet — check your connection and retry.'
            : e is ApiException && e.isServerError
            ? 'Server problem — retry in a moment.'
            : ordersStringsHi['errorTitle'];
        _isOffline = e is ApiException && e.isOffline;
        _isServerError = e is ApiException && e.isServerError;
      }
      _onPollError();
    }
    _notify();
  }

  Future<void> refresh() async {
    _cursor = null;
    await load();
  }

  Future<void> loadMore() async {
    final cursor = _cursor;
    if (!_hasMore ||
        cursor == null ||
        _status == OrdersListStatus.loading ||
        _loadingMore) {
      return;
    }
    _loadingMore = true;
    _loadMoreFailed = false;
    _loadMoreError = null;
    _notify();
    final gen = _generation;
    try {
      final page = await _repo.fetchOrders(cursor: cursor);
      if (gen != _generation) return;
      // Cursor pages can overlap (a new order shifts the window) — dedupe by
      // id so "Load more" never renders the same card twice.
      final seen = _all.map((o) => o.id).toSet();
      for (final order in page.orders) {
        if (seen.add(order.id)) _all.add(order);
      }
      _cursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
      _onPollSuccess();
    } catch (e) {
      if (gen != _generation) return;
      _loadMoreFailed = true;
      _loadMoreError = e is ApiException && e.isOffline
          ? 'No internet — check your connection and retry.'
          : e is ApiException && e.isServerError
          ? 'Server problem — retry in a moment.'
          : 'Could not load more orders.';
      _onPollError();
    } finally {
      if (gen == _generation) {
        _loadingMore = false;
        _notify();
      }
    }
  }

  /// Footer retry for a failed [loadMore].
  Future<void> retryLoadMore() async {
    if (_loadingMore) return;
    _loadMoreFailed = false;
    _loadMoreError = null;
    _notify();
    await loadMore();
  }

  /// Detail refresh for the tracking screen (poll target).
  Future<Order?> refreshOrder(String id) async {
    final gen = _generation;
    try {
      final fresh = await _repo.fetchOrder(id);
      if (gen != _generation) return findById(id);
      final idx = _all.indexWhere((o) => o.id == id);
      if (idx >= 0) {
        _all[idx] = fresh;
      } else {
        _all.add(fresh);
      }
      _detailFailed = false;
      _detailOffline = false;
      _detailServerError = false;
      _onPollSuccess();
      _notify();
      return fresh;
    } catch (e) {
      if (gen != _generation) return findById(id);
      _detailFailed = true;
      _detailOffline = e is ApiException && e.isOffline;
      _detailServerError = e is ApiException && e.isServerError;
      _onPollError();
      _notify();
      return findById(id);
    }
  }

  String? cancelErrorMessage;

  Future<bool> cancel(String id, String reasonCode) async {
    if (_actionBusy) return false;
    _actionBusy = true;
    _notify();
    final gen = _generation;
    try {
      cancelErrorMessage = null;
      final updated = await _repo.cancelOrder(id, reasonCode);
      if (gen != _generation) return true;
      _replace(updated);
      return true;
    } on ApiException catch (e) {
      cancelErrorMessage = e.message;
      return false;
    } catch (e) {
      cancelErrorMessage = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _actionBusy = false;
      _notify();
    }
  }

  Future<bool> confirmDelivery(
    String id, {
    required bool received,
    bool cashPaid = true,
    String notes = '',
    bool rescheduleToday = false,
  }) async {
    if (_actionBusy) return false;
    _actionBusy = true;
    _notify();
    final gen = _generation;
    try {
      final updated = await _repo.confirmDelivery(
        id,
        received: received,
        cashPaid: cashPaid,
        notes: notes,
        rescheduleToday: rescheduleToday,
      );
      if (gen != _generation) return true;
      _replace(updated);
      return true;
    } catch (_) {
      return false;
    } finally {
      _actionBusy = false;
      _notify();
    }
  }

  Future<bool> reschedule(String id, DateTime windowStart) async {
    if (_actionBusy) return false;
    _actionBusy = true;
    _notify();
    final gen = _generation;
    try {
      final updated = await _repo.rescheduleOrder(id, windowStart);
      if (gen != _generation) return true;
      _replace(updated);
      return true;
    } catch (_) {
      return false;
    } finally {
      _actionBusy = false;
      _notify();
    }
  }

  Future<RateResult> rate(String id, int stars) async {
    if (stars < 1 || stars > 5) return RateResult.failed;
    final gen = _generation;
    try {
      final updated = await _repo.submitRating(id, stars);
      if (gen != _generation) return RateResult.success;
      _replace(updated);
      return RateResult.success;
    } on StateError catch (e) {
      // Local repo guard — anything else (not found / not delivered) failed.
      return e.message == 'already rated'
          ? RateResult.alreadyRated
          : RateResult.failed;
    } on ApiException catch (e) {
      return e.code == 'ALREADY_RATED'
          ? RateResult.alreadyRated
          : RateResult.failed;
    } catch (_) {
      return RateResult.failed;
    }
  }

  /// Owner reissue for an expired/locked/unavailable code. Never called by
  /// polling; only a deliberate tap. Returns copy for the inline card error.
  Future<DeliveryCodeReissueResult> reissueDeliveryCode(String id) async {
    if (_reissueBusy) {
      return const DeliveryCodeReissueResult.failed('Please wait…');
    }
    _reissueBusy = true;
    _notify();
    final gen = _generation;
    try {
      final raw = await _repo.reissueDeliveryCode(id);
      if (gen != _generation) {
        return const DeliveryCodeReissueResult.success();
      }
      final rawState = raw['delivery_otp_state']?.toString() ?? '';
      final state =
          const {
            'none',
            'active',
            'expired',
            'locked',
            'unavailable',
            'used',
          }.contains(rawState)
          ? rawState
          : 'active';
      final rawCode = raw['delivery_otp']?.toString();
      final code = rawCode == null || rawCode.isEmpty ? null : rawCode;
      final resolvedState = state == 'active' && code == null
          ? 'unavailable'
          : state;
      final expiresAt = DateTime.tryParse(
        raw['delivery_otp_expires_at']?.toString() ?? '',
      );
      final reissueAvailable = raw['delivery_otp_reissue_available'] == true;
      final idx = _all.indexWhere((o) => o.id == id);
      if (idx >= 0) {
        _all[idx] = _all[idx].withDeliveryCode(
          code: code,
          expiresAt: expiresAt,
          state: resolvedState,
          reissueAvailable: reissueAvailable,
        );
      } else {
        await refreshOrder(id);
      }
      return const DeliveryCodeReissueResult.success();
    } on ApiException catch (e) {
      if (gen != _generation) {
        return const DeliveryCodeReissueResult.success();
      }
      if (e.code == 'CODE_ACTIVE') {
        // Race with the 24h rollover/clients: sync the truth, then explain.
        await refreshOrder(id);
        return const DeliveryCodeReissueResult.failed(
          'This code is still active. It will show again on refresh.',
        );
      }
      if (e.statusCode == 429) {
        final wait = (e.retryAfterSeconds ?? 60).clamp(1, 3600);
        return DeliveryCodeReissueResult.failed(
          'Too many new codes. Try again in ${wait}s.',
          retryAfterSeconds: wait,
        );
      }
      if (e.statusCode == 404 ||
          (e.statusCode == 409 && e.code != 'CODE_ACTIVE')) {
        return const DeliveryCodeReissueResult.failed(
          'This delivery can no longer get a new code.',
        );
      }
      if (e.isOffline) {
        return const DeliveryCodeReissueResult.failed(
          'No internet — check your connection and try again.',
        );
      }
      if (e.isServerError) {
        return const DeliveryCodeReissueResult.failed(
          'Server problem — retry in a moment.',
        );
      }
      return const DeliveryCodeReissueResult.failed(
        'Could not get a new code. Try again.',
      );
    } catch (_) {
      return const DeliveryCodeReissueResult.failed(
        'Could not get a new code. Try again.',
      );
    } finally {
      if (gen == _generation) {
        _reissueBusy = false;
        _notify();
      }
    }
  }

  /// True on the FIRST delivered view (or manual tap while [Order.canRate]).
  bool shouldAutoPrompt(Order order) {
    return order.state == OrderState.delivered &&
        !order.rated &&
        !_ratingPrompted.contains(order.id);
  }

  void markRatingPrompted(String id) {
    _ratingPrompted.add(id);
  }

  /// tel: dialer via url_launcher (dep landed in F1). false → SnackBar.
  Future<bool> openDialer(String phone) async {
    try {
      return await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {
      return false;
    }
  }

  /// wa.me deep link with prefilled order context; false → SnackBar.
  Future<bool> openWhatsApp(String orderContext) async {
    final digits = kSupportPhone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse(
      'https://wa.me/$digits?text=${Uri.encodeComponent(orderContext)}',
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Tracking poll: 60s tick with backoff to 300s (contract: no live dot,
  /// window + rider via poll + push; poll is the fallback).
  void startTracking(String id) {
    _trackingId = id;
    _trackingPaused = false;
    _armTracking();
  }

  /// Pause while the app is backgrounded; the id is kept so resume can re-arm.
  void pauseTracking() {
    _trackingPaused = true;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void resumeTracking() {
    if (_trackingId == null) return;
    _trackingPaused = false;
    _armTracking();
  }

  void stopTracking() {
    _trackingId = null;
    _trackingPaused = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _armTracking() {
    _pollTimer?.cancel();
    final id = _trackingId;
    if (id == null || _trackingPaused || _disposed) return;
    _pollTimer = Timer.periodic(Duration(seconds: _pollSeconds), (_) async {
      if (_disposed || _trackingPaused) return;
      await refreshOrder(id);
      // Re-arm at the (possibly backed-off) cadence.
      if (!_disposed) _armTracking();
    });
  }

  @visibleForTesting
  void simulatePollError() => _onPollError();

  @visibleForTesting
  void simulatePollSuccess() => _onPollSuccess();

  void _onPollError() {
    _pollSeconds = (_pollSeconds * 2).clamp(pollBaseSeconds, pollMaxSeconds);
  }

  void _onPollSuccess() {
    _pollSeconds = pollBaseSeconds;
  }

  void _replace(Order updated) {
    final idx = _all.indexWhere((o) => o.id == updated.id);
    if (idx >= 0) {
      _all[idx] = updated;
    } else {
      _all.add(updated);
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }
}
