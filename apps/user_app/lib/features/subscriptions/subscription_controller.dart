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
  'duesTitle': 'OUTSTANDING DUES',
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
  'cancelTitle': 'Cancel subscription',
  'cancelBody':
      'Unused water (if prepaid) and the jar deposit are refunded '
      'to your UPI after pickup. The server calculates the final amounts.',
  'cancelReason': 'Why are you cancelling?',
  'cancelUpi': 'UPI ID for the refund',
  'cancelUpiHint': 'e.g. 9876543210@upi',
  'cancelConfirm': 'Cancel plan & schedule pickup',
  'cancelDone': 'Subscription canceled',
  'cancelDoneBody':
      'Your subscription is canceled. Bottle pickup is '
      'scheduled and the refund is on its way.',
  'planTitle': 'Build a monthly plan',
  'planEyebrow': 'MONTHLY PLAN',
  'jarsPerDelivery': 'Jars per delivery',
  'jarSku': '20L refill jar',
  'rhythm': 'Delivery rhythm',
  'daily': 'Daily',
  'alternate': 'Alternate days',
  'weekly': 'Weekly',
  'address': 'Delivery address',
  'noAddress': 'No saved address. Add one in Profile, then come back.',
  'estimateTitle': 'First-delivery estimate',
  'estimateWater': 'Water',
  'estimateDeposit': 'Refundable jar deposit',
  'estimateTotal': 'Total today',
  'estimateNote':
      'Live amount from the server. You pay per delivery after this.',
  'estimateFailed': 'Could not load the estimate.',
  'starting': 'Starting…',
  'createFailed': 'Could not start the plan.',
  'signedOutPlan': 'Sign in to start a plan.',
  'payloadMismatch':
      'The plan changed while submitting. Review it and try again.',
  'planStarted': 'Plan started.',
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
    this.rateVersion = '',
  });

  final int totalPaise;
  final int? waterBillPaise;
  final int? depositDuePaise;
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
      final raw = await _api.listSubscriptions();
      final labels = await _addressLabels();
      _items = raw
          .whereType<Map<String, dynamic>>()
          .map((j) => SubscriptionEntry.fromApi(j, addressLabels: labels))
          .toList();
      await _loadDues();
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
        'error': e.isNetwork
            ? subStrings['offline']
            : (e.message.isNotEmpty ? e.message : subStrings['duesPayFailed']),
      };
    } catch (_) {
      return {'error': subStrings['duesPayFailed']};
    } finally {
      _busy = false;
      _notify();
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
        'error': e.isNetwork
            ? subStrings['offline']
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
    if (e.isNetwork) return subStrings['offline']!;
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
