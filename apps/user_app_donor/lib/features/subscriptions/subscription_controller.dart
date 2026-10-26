// S6 — Subscriptions state: list + real pause/skip/cancel states + dues.
//
// Behaviour ported from the legacy screen (apps/user_app_legacy_flutter/
// features/subscriptions): list → empty → error, pause range validation,
// resume ≥24h guard, skip with late-cut-off CTA, cancel with refund target.
// Money law: every amount here is a server field (`due_today_paise`,
// `monthly_estimate_paise`, `GET /billing/dues`) — never client math.
// States.md: loading skeleton → empty → error + retry; every mutation is
// pending → success (snackbar) / failure with a reason.
// Copy: legacy Hinglish translated to donor English (owner decision §11.4).
//
// Backend notes:
// - `GET /subscriptions` returns `{data:[...]}` (ApiClient unwraps).
// - A canceled row keeps `status='paused'` in D1, so `canceled_at` wins.
// - `POST /skips` returns 201 `{late_skip: bool}` instead of a 4xx; both that
//   field and a hypothetical LATE_SKIP error are honoured.
// - `POST /payments/dues-intent` has no body; the Idempotency-Key header is
//   the whole contract. The key stays stable while the dues amount is
//   unchanged, so a double tap replays one intent instead of charging twice.

// ignore_for_file: prefer_initializing_formals
// WHY: the public constructor takes `api`, but the field is private (`_api`).
// `this._api` would leak an underscore name into the named-parameter API.

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';

/// Screen copy (English; keys match the legacy controller contract).
const Map<String, String> subStrings = {
  'title': 'Subscriptions',
  'emptyTitle': 'No subscription yet',
  'emptyHint':
      'Set a rhythm and your jars arrive without reordering. The '
      'first-delivery estimate comes from the server before you start.',
  'buildPlan': 'Build a plan',
  'startPlan': 'Start this plan',
  'pause': 'Pause',
  'resume': 'Resume',
  'skipToday': 'Skip today',
  'cancel': 'Cancel',
  'active': 'Active',
  'paused': 'Paused',
  'canceled': 'Canceled',
  'pausedUntil': 'Paused until',
  'nextRun': 'Next delivery',
  'windowLabel': 'Window',
  'monthlyEstimate': 'Monthly estimate',
  'dueToday': 'Due today',
  'canceledNote': 'Canceled. Bottle pickup is scheduled by the server.',
  'duesTitle': 'Outstanding dues',
  'payDues': 'Pay dues',
  'wallet': 'Wallet',
  'duesPayTitle': 'UPI payment request created',
  'duesPayBody':
      'Complete the payment in your UPI app. Dues clear automatically '
      'after the provider confirms it.',
  'duesPayRef': 'Reference',
  'duesPayFailed': 'Could not start the dues payment.',
  'retry': 'Try again',
  'loadFailed': 'Could not load your plans.',
  'offline': "You're offline. Check your connection and try again.",
  'signedOut': 'Sign in to see your plans.',
  'restricted': 'This account cannot view plans. Contact support.',
  'refreshFailed': 'Could not refresh. Showing the last loaded plans.',
  'notFound': 'This plan is no longer available.',
  'pauseTitle': 'Pause deliveries',
  'pauseBody':
      'Choose the dates you will be away. Deliveries resume '
      'automatically after the hold.',
  'fromDate': 'From',
  'toDate': 'To',
  'pauseConfirm': 'Confirm pause',
  'errRange': 'End date must be after the start date.',
  'resumeNote': 'Pick a date at least 24 hours from now.',
  'resumeTooSoon': 'The server needs 24 hours notice. Next available date: ',
  'lateSkipTitle': 'Cut-off has passed',
  'lateSkipBody': "Today's delivery was not skipped. Call support at ",
  'lateSkipTail': ' so the vendor is informed.',
  'skipConfirmTitle': "Skip today's delivery?",
  'skipConfirmBody':
      "Today's jars won't be delivered. Your next delivery stays as "
      'scheduled.',
  'skipConfirm': 'Skip today',
  'skipKeep': 'Keep delivery',
  'ok': 'OK',
  'saved': 'Done',
  'cancelTitle': 'Cancel this plan?',
  'cancelBody':
      "We'll stop future deliveries. If you paid for deliveries you won't "
      'receive, we will calculate that refund after pickup. Jar deposits are '
      'refunded when we collect the jars.',
  'cancelReason': 'Why are you cancelling?',
  'cancelUpi': 'UPI ID for any refund',
  'cancelUpiHint': 'e.g. 9876543210@upi',
  'cancelConfirm': 'Cancel plan',
  'cancelDone': 'Plan canceled',
  'cancelDoneBody':
      'Future deliveries are stopped. If a refund is due, we will process it '
      'to your UPI after pickup. Nothing is refunded for deliveries that were '
      'never paid.',
  'cancelNoRefund': 'No refund is due because no deliveries were prepaid.',
  'planTitle': 'Build a delivery plan',
  'planEyebrow': 'NEW PLAN',
  'jarsPerDelivery': 'Jars per delivery',
  'jarSku': '20L refill jar',
  'rhythm': 'Delivery rhythm',
  'daily': 'Daily',
  'alternate': 'Alternate days',
  'weekly': 'Weekly',
  'address': 'Delivery address',
  'noAddress': 'No saved address. Add one in Profile, then come back.',
  'estimateTitle': 'First delivery estimate',
  'estimatePrepaidTitle': 'Monthly prepaid estimate',
  'estimateWater': 'Water',
  'estimateDeposit': 'Refundable jar deposit',
  'estimateMonthlyTopup': 'Monthly water top-up',
  'estimateDepositFirst': 'Refundable jar deposit (first delivery)',
  'estimateTotal': 'First delivery total',
  'estimateNote':
      'No payment is collected now. This is what the first delivery will '
      'cost, billed as usual.',
  'estimateFailed': 'Could not load the estimate.',
  'starting': 'Creating plan…',
  'createFailed': 'Could not create the plan.',
  'signedOutPlan': 'Sign in to start a plan.',
  'payloadMismatch':
      'The plan changed while submitting. Review it and try again.',
  'planStarted': 'Plan created. No payment was collected.',
  'planStartedPrepaid':
      'Plan created. Deliveries start after the monthly top-up is confirmed.',
  'payment': 'Payment',
  'billing': 'Billing',
  'payCod': 'Cash on delivery',
  'payUpi': 'UPI',
  'billPerDelivery': 'Pay for each delivery',
  'billPrepaid': 'Monthly prepaid',
  'billPostpaid': 'Monthly bill',
  'billPerDeliveryNote':
      "No payment is collected now. You'll pay at each delivery.",
  'billPrepaidNote':
      "You'll pay one month of water up front by UPI. Each delivery is "
      'deducted from that balance. The jar deposit is charged on the first '
      'delivery.',
  'billPostpaidNote':
      'No payment is collected now. Deliveries add to your monthly bill, '
      'paid by UPI at the end of the month.',
  'monthlyNeedsUpi': 'Monthly plans are paid by UPI.',
  'billingPending': 'Awaiting payment',
  'prepaidBalance': 'Prepaid water balance',
  'prepaidCovers':
      'Covers water only. The jar deposit is charged on the first delivery.',
  'addTopUp': 'Add monthly top-up',
  'lowBalance': 'Prepaid balance is low. Add a top-up to resume deliveries.',
  'billingPrepaid': 'Monthly prepaid',
  'billingPostpaid': 'Monthly bill',
  'billingPerDelivery': 'Per delivery',
  'paymentUpi': 'UPI',
  'paymentCod': 'Cash on delivery',
  'topupTitle': 'Complete the monthly top-up',
  'topupBody':
      'Pay by UPI to start deliveries. Each delivery is deducted from this '
      'balance. The jar deposit is charged separately on the first delivery.',
  'topupStarted': 'Payment request created',
  'topupPendingTitle': 'Waiting for payment',
  'topupPendingBody':
      "We'll start deliveries as soon as the provider confirms the payment. "
      'This can take a minute.',
  'topupCheck': 'Check payment',
  'topupStillPending':
      'Not confirmed yet. No deliveries start until the payment is confirmed.',
  'topupConfirmed': 'Top-up confirmed. Deliveries are active.',
  'topupFailed': 'Could not start the monthly top-up.',
  'topupBusy': 'A payment link is already being created. Try again shortly.',
  'topupCopy': 'Copy link',
  'topupCopied': 'Payment link copied.',
  'topupNoApp':
      'Your UPI app did not open. Copy the link and pay in any UPI app.',
  'topupOpen': 'Open UPI app',
  'topupDone': 'Done',
  'addressFallback': 'Delivery address',
  'addJar': 'Add a jar',
  'removeJar': 'Remove a jar',
  'refresh': 'Refresh',
  'close': 'Close',
};

/// `5600` → `₹56`; `5650` → `₹56.50` (display only — never math).
String rupeesLabel(int paise) => formatInr(paise);

/// User-facing address label from an address payload (server-owned fields).
String addressLabelOf(Map<String, dynamic> a) {
  String text(Object? v) => v is String ? v.trim() : '';
  final label = text(a['label']);
  if (label.isNotEmpty) return label;
  final parts = [
    text(a['house']),
    text(a['street']),
    text(a['area']),
  ].where((p) => p.isNotEmpty).toList();
  if (parts.isNotEmpty) return parts.join(', ');
  final formatted = text(a['formatted']);
  return formatted.isNotEmpty ? formatted : subStrings['addressFallback']!;
}

enum SubStatus { initial, loading, loaded, error }

/// One subscription row, parsed from `GET /subscriptions`.
@immutable
class SubscriptionEntry {
  const SubscriptionEntry({
    required this.id,
    required this.addressLabel,
    required this.qty,
    required this.skuMix,
    required this.window,
    this.paused = false,
    this.canceled = false,
    this.holdFrom,
    this.holdTo,
    this.nextRun,
    this.dueTodayPaise,
    this.monthlyEstimatePaise,
    this.billingMode = 'per_delivery',
    this.paymentMethod = 'cod',
    this.billingStatus = 'active',
    this.creditBalancePaise = 0,
    this.lowBalance = false,
  });

  final String id;
  final String addressLabel;
  final int qty;

  /// `refill` | `container` (server value, never invented).
  final String skuMix;

  /// Stored delivery window; empty when the server did not set one.
  final String window;

  final bool paused;
  final bool canceled;
  final String? holdFrom;
  final String? holdTo;
  final String? nextRun;

  /// Server preview for today (paise) — null when the field is absent.
  final int? dueTodayPaise;

  /// Server 30-day estimate (paise) — null when the field is absent.
  final int? monthlyEstimatePaise;

  /// `per_delivery` | `monthly_prepaid` | `monthly_postpaid` (server value).
  final String billingMode;

  /// `upi` | `cod` (server value).
  final String paymentMethod;

  /// `active` | `pending_payment` | `canceled` (server value).
  final String billingStatus;

  /// Collected prepaid credit still available for water (paise, server-set).
  final int creditBalancePaise;

  /// Server warning that the prepaid balance no longer covers one delivery.
  final bool lowBalance;

  bool get isPrepaid => billingMode == 'monthly_prepaid';

  /// Prepaid plan whose top-up has not been confirmed yet — never call this
  /// active: no delivery will run until the server flips billing_status.
  bool get awaitingPayment =>
      !canceled && isPrepaid && billingStatus == 'pending_payment';

  static SubscriptionEntry fromApi(
    Map<String, dynamic> j, {
    Map<String, String> addressLabels = const {},
  }) {
    final status = (j['status'] ?? '').toString();
    final canceled = j['canceled_at'] != null || status == 'canceled';
    // Canceled rows keep status='paused' in D1 — canceled must win.
    final paused = !canceled && (j['paused'] == true || status == 'paused');
    String? optional(Object? v) {
      final s = (v ?? '').toString();
      return s.isEmpty ? null : s;
    }

    final addressId = (j['address_id'] ?? '').toString();
    return SubscriptionEntry(
      id: (j['id'] ?? '').toString(),
      addressLabel: addressLabels[addressId] ?? subStrings['addressFallback']!,
      qty: (j['qty'] as num?)?.toInt() ?? 0,
      skuMix: (j['sku_mix'] ?? 'refill').toString(),
      window: (j['window'] ?? '').toString(),
      paused: paused,
      canceled: canceled,
      holdFrom: optional(j['hold_from']),
      holdTo: optional(j['hold_to']),
      nextRun: optional(j['next_run']),
      dueTodayPaise: (j['due_today_paise'] as num?)?.toInt(),
      monthlyEstimatePaise: (j['monthly_estimate_paise'] as num?)?.toInt(),
      billingMode: (j['billing_mode'] ?? 'per_delivery').toString(),
      paymentMethod: (j['payment_method'] ?? 'cod').toString(),
      billingStatus: (j['billing_status'] ?? 'active').toString(),
      creditBalancePaise: (j['credit_balance_paise'] as num?)?.toInt() ?? 0,
      lowBalance: j['low_balance'] == true,
    );
  }
}

/// `POST /subscriptions/estimate` payload (first cycle: water + deposit).
@immutable
class SubscriptionEstimate {
  const SubscriptionEstimate({
    required this.totalPaise,
    this.waterBillPaise,
    this.depositDuePaise,
    this.monthlyTopupPaise,
    this.rateVersion = '',
  });

  final int totalPaise;
  final int? waterBillPaise;
  final int? depositDuePaise;

  /// 30 days of water (server-computed); the prepaid amount, deposit excluded.
  final int? monthlyTopupPaise;
  final String rateVersion;

  static SubscriptionEstimate fromApi(Map<String, dynamic> j) {
    final total = (j['total'] as num?)?.toInt();
    if (total == null) {
      throw const FormatException('estimate missing total');
    }
    return SubscriptionEstimate(
      totalPaise: total,
      waterBillPaise: (j['water_bill'] as num?)?.toInt(),
      depositDuePaise: (j['deposit_due'] as num?)?.toInt(),
      monthlyTopupPaise: (j['monthly_topup_paise'] as num?)?.toInt(),
      rateVersion: (j['rate_version'] ?? '').toString(),
    );
  }
}

/// List + mutation state for the Subscriptions tab.
class SubscriptionController extends ChangeNotifier {
  SubscriptionController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  SubStatus _status = SubStatus.initial;
  List<SubscriptionEntry> _items = const [];
  String? _errorMessage;
  bool _busy = false;

  /// Outstanding dues from `GET /billing/dues`; null = unknown (hidden, never
  /// a fake Rs 0).
  int? _duesPaise;

  /// Stable per dues amount — server replays the same intent for the same key.
  String _duesIdemKey = const Uuid().v4();

  SubStatus get status => _status;
  List<SubscriptionEntry> get items => List.unmodifiable(_items);
  String? get errorMessage => _errorMessage;
  bool get busy => _busy;
  int? get duesPaise => _duesPaise;

  Future<void> load() async {
    if (_status == SubStatus.loading) return;
    _status = SubStatus.loading;
    _errorMessage = null;
    _notify();
    try {
      // Independent reads run together; only the list/dues pair is needed for
      // the first paint, but the labels must not serialize behind them.
      final subsFuture = _api.listSubscriptions();
      final labelsFuture = _addressLabels();
      final duesFuture = _loadDues();
      final raw = await subsFuture;
      final labels = await labelsFuture;
      _items = raw
          .whereType<Map<String, dynamic>>()
          .map((j) => SubscriptionEntry.fromApi(j, addressLabels: labels))
          .toList();
      await duesFuture;
      _status = SubStatus.loaded;
    } on ApiException catch (e) {
      _status = SubStatus.error;
      _errorMessage = _loadError(e);
    } catch (_) {
      _status = SubStatus.error;
      _errorMessage = subStrings['loadFailed'];
    }
    _notify();
  }

  /// Pause with range validation (end > start). Returns a copy key, or null.
  Future<String?> pause(String id, String from, String to) async {
    if (to.compareTo(from) <= 0) return 'errRange';
    _busy = true;
    _notify();
    try {
      await _api.pauseSubscription(id, from, to);
      await load();
      return null;
    } on ApiException catch (e) {
      return _actionError(e);
    } catch (_) {
      return 'loadFailed';
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Resume needs ≥24h notice; the server is the final judge (422 supplies
  /// `next_valid_date` in details — shown instead of a dead error).
  Future<String?> resume(String id, String preferredDate) async {
    final today = ApiClient.dateOnly(DateTime.now());
    if (preferredDate.compareTo(today) <= 0) return 'resumeNote';
    _busy = true;
    _notify();
    try {
      await _api.resumeSubscription(id, preferredDate);
      await load();
      return null;
    } on ApiException catch (e) {
      if (e.code == 'RESUME_TOO_SOON' || e.statusCode == 422) {
        final next = e.details?['next_valid_date'];
        final day = next is String ? next.split('T').first : null;
        if (day != null && day.isNotEmpty) {
          return '${subStrings['resumeTooSoon']}$day';
        }
      }
      return _actionError(e);
    } catch (_) {
      return 'loadFailed';
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Skip today. Returns `lateSkip` after the cutoff (never a silent skip).
  Future<String?> skipToday(String id) async {
    _busy = true;
    _notify();
    try {
      final res = await _api.skipSubscriptionDay(
        id,
        ApiClient.dateOnly(DateTime.now()),
      );
      await load();
      return res['late_skip'] == true ? 'lateSkip' : null;
    } on ApiException catch (e) {
      if (e.code == 'LATE_SKIP') return 'lateSkip';
      return _actionError(e);
    } catch (_) {
      return 'loadFailed';
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Full-dues UPI intent (S7 transport gap closed via the sanctioned
  /// [ApiClient.send]). Returns the server `{payment, link, provider_ref}` or
  /// `{'error': message}`; the link is informational only and must never be
  /// auto-launched (fake provider — Razorpay webhook is the money truth).
  Future<Map<String, dynamic>?> payDues() async {
    final dues = _duesPaise;
    if (_busy || dues == null || dues <= 0) return null;
    _busy = true;
    _notify();
    try {
      final res = await _api.send(
        'POST',
        '/payments/dues-intent',
        body: const <String, dynamic>{},
        idempotencyKey: _duesIdemKey,
      );
      return res is Map<String, dynamic>
          ? res
          : {'error': subStrings['duesPayFailed']};
    } on ApiException catch (e) {
      // 409/422 = dues moved (already settled or nothing left) — refresh so
      // the strip tells the truth instead of repeating a dead intent.
      if (e.statusCode == 409 || e.statusCode == 422) await _loadDues();
      return {
        'error': e.isOffline
            ? subStrings['offline']
            : e.isServerError
            ? 'Server problem — retry in a moment.'
            : (e.message.isNotEmpty ? e.message : subStrings['duesPayFailed']),
      };
    } catch (_) {
      return {'error': subStrings['duesPayFailed']};
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Start (or replay) one prepaid top-up intent. The key stays stable per
  /// plan until the server confirms payment, so a double tap cannot mint a
  /// second provider order. Returns the server `{charge, link, provider_ref}`
  /// or `{'error': message}`; launching the link is the screen's job.
  final Map<String, String> _topUpKeys = {};

  Future<Map<String, dynamic>?> topUp(String subId) async {
    if (_busy) return null;
    _busy = true;
    _notify();
    final key = _topUpKeys.putIfAbsent(subId, () => const Uuid().v4());
    try {
      return await _api.subscriptionIntent(
        subscriptionId: subId,
        idempotencyKey: key,
      );
    } on ApiException catch (e) {
      return {
        'error': e.code == 'INTENT_PENDING'
            ? subStrings['topupBusy']
            : e.isOffline
            ? subStrings['offline']
            : e.isServerError
            ? 'Server problem — retry in a moment.'
            : (e.message.isNotEmpty ? e.message : subStrings['topupFailed']),
      };
    } catch (_) {
      return {'error': subStrings['topupFailed']};
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Re-reads the plan and reports whether the prepaid top-up landed.
  /// Only `billing_status == 'active'` counts — `pending_payment` means the
  /// provider has not confirmed yet, so no delivery will run.
  Future<bool> confirmTopUp(String subId) async {
    try {
      final raw = await _api.listSubscriptions();
      Map<String, dynamic>? row;
      for (final item in raw.whereType<Map>()) {
        final j = Map<String, dynamic>.from(item);
        if ((j['id'] ?? '').toString() == subId) {
          row = j;
          break;
        }
      }
      if (row == null) return false;
      final active =
          (row['billing_status'] ?? '') == 'active' &&
          row['canceled_at'] == null;
      if (active) {
        _topUpKeys.remove(subId);
        await load();
      }
      return active;
    } catch (_) {
      return false;
    }
  }

  /// Cancel. Success returns the server outcome (refund fields for the
  /// confirmation dialog); failure returns `{'error': message}`.
  Future<Map<String, dynamic>?> cancelSubscription(
    String id,
    String reason,
    String upiId,
  ) async {
    _busy = true;
    _notify();
    try {
      final res = await _api.cancelSubscription(
        id: id,
        reason: reason,
        upiId: upiId,
      );
      await load();
      return res;
    } on ApiException catch (e) {
      return {
        'error': e.isOffline
            ? subStrings['offline']
            : e.isServerError
            ? 'Server problem — retry in a moment.'
            : (e.message.isNotEmpty ? e.message : subStrings['loadFailed']),
      };
    } catch (_) {
      return {'error': subStrings['loadFailed']};
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<Map<String, String>> _addressLabels() async {
    try {
      final raw = await _api.listAddresses();
      final labels = <String, String>{};
      for (final a in raw.whereType<Map>()) {
        final j = Map<String, dynamic>.from(a);
        final id = (j['id'] ?? '').toString();
        if (id.isNotEmpty) labels[id] = addressLabelOf(j);
      }
      return labels;
    } catch (_) {
      // Label enrichment is best-effort — plans still render honestly.
      return const {};
    }
  }

  Future<void> _loadDues() async {
    final before = _duesPaise;
    try {
      final dues = await _api.billingDues();
      final value = (dues['dues'] as num?)?.toInt();
      _duesPaise = value != null && value > 0 ? value : null;
    } catch (_) {
      _duesPaise = null; // unknown, not zero
    }
    // A changed (or newly known) amount is a new money request; an unchanged
    // one keeps its key so repeat taps replay the same intent.
    if (_duesPaise != before) _duesIdemKey = const Uuid().v4();
  }

  String _loadError(ApiException e) {
    if (e.statusCode == 401) return subStrings['signedOut']!;
    if (e.statusCode == 403) return subStrings['restricted']!;
    if (e.isOffline) return subStrings['offline']!;
    if (e.isServerError) return 'Server problem — retry in a moment.';
    return subStrings['loadFailed']!;
  }

  String _actionError(ApiException e) {
    if (e.statusCode == 404) return 'notFound';
    return _loadError(e);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
