// F4 — Orders state for the Shodasha user app (branch 004-user-app-build).
//
// Backend contract: Feature_docs/backend/api-contract.md §4.4
// (POST /orders idempotent + quote-lock, GET /orders cursor paging,
// GET /orders/{id} + /tracking, POST cancel pre-dispatch only with
// {reason} + Idempotency-Key, POST reschedule pre-dispatch only with
// {window_start}, POST rating once per delivered order) and
// Feature_docs/synthesis/user-flows.md flows 3 (tracking, 30-min window,
// no live dot) + 5 (UPI/COD guards + reconcile + dues carry-forward).
//
// Wiring notes: tel:/wa.me launch via url_launcher with a SnackBar
// fallback when no handler exists (Phase 4 §4.5: support Open tries
// launchUrl first, clipboard copy is the fallback, never the primary).
// - Money is integer paise everywhere; [formatRupees] formats only for
//   display (2dp only when needed).

// TODO(F1): consolidate [ordersStringsHi] into lib/l10n/strings.dart
// (Hindi-first) and import it here. Do NOT create lib/l10n/ from F4.

// ignore_for_file: prefer_initializing_formals
// WHY: public ctor param `repo:` is the API (tests + F1 wiring construct
// this); private initializing formals are unusable from other libraries —
// same pattern as features/auth/auth_controller.dart.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

/// Hindi-first copy for the orders feature (local map per approved answer 1).
const Map<String, String> ordersStringsHi = {
  'ordersTitle': 'Mere orders',
  'searchHint': 'Order ID ya address khojein',
  'emptyTitle': 'Abhi koi order nahi',
  'emptyHint': 'Pehla order book karein — kal subah delivery',
  'noResultsTitle': 'Koi order nahi mila',
  'noResultsHint': 'Khoj badal kar dekhein',
  'errorTitle': 'Orders load nahi hue',
  'offlineTitle': 'Internet nahi — purane orders dikh rahe',
  'retry': 'Dobara try karein',
  'loadMore': 'Aur orders dekhein',
  'cancelTitle': 'Order cancel karein?',
  'cancelConfirm': 'Haan, cancel karein',
  'cancelKeep': 'Rehne dein',
  'cancelReasonLabel': 'Cancel ka kaaran chunein',
  'rescheduleTitle': 'Delivery ka time badlein',
  'rescheduleConfirm': 'Naya time pakka karein',
  'whatsappHelp': 'WhatsApp par madad',
  'whatsappFail': 'WhatsApp khul nahi paya — 8AM–8PM par try karein',
  'callFail': 'Dialer khul nahi paya',
  'callRider': 'Rider ko call karein',
  'deliveredBanner': 'Order deliver ho gaya',
  'cancelledBanner': 'Order cancel ho gaya',
  'failedBanner': 'Delivery fail ho gayi — support se baat karein',
  'rejectedBanner': 'Order reject ho gaya — paise wapas honge',
  'refundPending': 'Refund pending — rashi frozen, badlegi nahi',
  'duesNote': 'Baki rashi agle bill me jud jayegi',
  'rateTitle': 'Delivery kaisi rahi?',
  'rateSubmit': 'Rating bhejein',
  'rateThanks': 'Shukriya! Aapki rating mil gayi',
  'rateAgain': 'Rating ek baar hi di ja sakti hai',
  'complaintShortcut': 'Dikkat hai? Shikayat karein',
  'complaintStub': 'Shikayat screen jald aa rahi hai (order juda rahega)',
  'viewBill': 'Bill dekhein',
  'autoRefresh': 'Auto-refresh',
  'windowLabel': 'Delivery ka samay',
  'riderLabel': 'Rider',
};

/// F4 orders tokens — same Mode-1 restraint as auth (one accent, hairline
/// borders, radius 8, 48dp targets, no shadows/gradients/emoji/FAB/glass).
/// Wave 1 honesty: aliases of [ShodashaTheme] (the local #0369A1 blues
/// drifted from the locked #0284C7; one source stops the next drift).
class OrdersTokens {
  static const white = ShodashaTheme.bg;
  static const ink = ShodashaTheme.ink;
  static const muted = ShodashaTheme.muted;
  static const blue = ShodashaTheme.blue;
  static const blueTint = ShodashaTheme.blueTint;
  static const border = ShodashaTheme.border;
  static const radius = ShodashaTheme.radius;
  static const minTarget = ShodashaTheme.minTarget;
}

/// Canonical order lifecycle (contract §4.4 + §9 state machine).
/// Payment is a separate field, never a state.
enum OrderState {
  placed,
  accepted,
  picked,
  packed,
  assigned,
  dispatched,
  delivered,
  failed,
  cancelled,
  rejected,
}

/// Parses server state strings (unknown → placed, never crash on new states).
OrderState orderStateFromString(String raw) {
  switch (raw) {
    case 'accepted':
      return OrderState.accepted;
    case 'picked':
      return OrderState.picked;
    case 'packed':
      return OrderState.packed;
    case 'assigned':
      return OrderState.assigned;
    case 'dispatched':
      return OrderState.dispatched;
    case 'delivered':
      return OrderState.delivered;
    case 'failed':
      return OrderState.failed;
    case 'cancelled':
      return OrderState.cancelled;
    case 'rejected':
      return OrderState.rejected;
    case 'placed':
    default:
      return OrderState.placed;
  }
}

String orderStateToString(OrderState s) => s.name;

/// Cancel reasons — dropdown codes (approved answer 3), consistent with
/// complaint reason-code style ({reason} string on the wire).
enum CancelReason {
  changedMind('changed_mind', 'Mann badal gaya'),
  duplicate('duplicate', 'Duplicate order ho gaya'),
  orderedByMistake('ordered_by_mistake', 'Galti se order ho gaya'),
  delayed('delayed', 'Delivery me deri'),
  other('other', 'Kuch aur');

  const CancelReason(this.code, this.labelHi);
  final String code;
  final String labelHi;

  static CancelReason fromCode(String code) {
    for (final r in CancelReason.values) {
      if (r.code == code) return r;
    }
    return CancelReason.other;
  }
}

/// One 30-min reschedule slot inside 08:00–20:00 on a serviceable day.
@immutable
class RescheduleSlot {
  const RescheduleSlot({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  /// `09:00 - 09:30` (24h, zero-padded — unambiguous in Hindi UI too).
  String get label {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(start.hour)}:${two(start.minute)} - '
        '${two(end.hour)}:${two(end.minute)}';
  }

  @override
  bool operator ==(Object other) =>
      other is RescheduleSlot &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Next serviceable day slots: tomorrow onward, 30-min slots 08:00–20:00.
/// 014: all days water (no Sunday skip — matches booking + GET /windows).
List<RescheduleSlot> nextServiceSlots({DateTime? from}) {
  var day = (from ?? DateTime.now()).add(const Duration(days: 1));
  day = DateTime(day.year, day.month, day.day);
  final slots = <RescheduleSlot>[];
  for (var h = 8; h < 20; h++) {
    for (final m in [0, 30]) {
      final start = day.add(Duration(hours: h, minutes: m));
      slots.add(RescheduleSlot(start: start, end: start.add(
        const Duration(minutes: 30),
      )));
    }
  }
  return slots;
}

/// ₹ formatting: paise ints, 2dp ONLY when needed (5600 → ₹56, 5650 → ₹56.50).
String formatRupees(int paise) {
  final sign = paise < 0 ? '-' : '';
  final abs = paise.abs();
  if (abs % 100 == 0) return '$sign\u20B9${abs ~/ 100}';
  return '$sign\u20B9${(abs / 100).toStringAsFixed(2)}';
}

/// Order entity — money in integer paise, frozen server-side (contract §4.4).
@immutable
class Order {
  const Order({
    required this.id,
    required this.state,
    required this.windowStart,
    this.windowEnd,
    this.riderName,
    this.riderPhone,
    this.itemSummary = '',
    this.addressLabel = '',
    this.waterBillPaise = 0,
    this.depositDuePaise = 0,
    this.capChargePaise = 0,
    this.prevDuesPaise = 0,
    this.paymentsPaise = 0,
    this.totalPaise = 0,
    this.refundPending = false,
    this.refundAmountPaise = 0,
    this.rated = false,
    this.stars,
    this.createdAt,
    this.refillQty = 0,
    this.containerQty = 0,
    this.paymentMode = 'cod',
    this.paymentStatus = 'unpaid',
    this.deliveryOtp,
    this.stopsAhead,
  });

  final String id;
  final OrderState state;
  final DateTime windowStart;
  final DateTime? windowEnd;
  final String? riderName;
  final String? riderPhone;
  final int? stopsAhead;
  final String itemSummary;
  final String addressLabel;
  final int waterBillPaise;
  final int depositDuePaise;
  final int capChargePaise;
  final int prevDuesPaise;
  final int paymentsPaise;
  final int totalPaise;
  final bool refundPending;
  final int refundAmountPaise;
  final bool rated;
  final int? stars;
  final DateTime? createdAt;

  /// Per-SKU quantities for one-tap reorder (0 = unknown, e.g. legacy rows).
  final int refillQty;
  final int containerQty;

  /// 015: payment visibility (UPI/COD + paid state) on timeline + bill.
  final String paymentMode;
  final String paymentStatus;

  /// F1: PoD delivery code (server detail only, dispatched/assigned).
  /// Shown once on tracking so the customer can read it to the rider.
  final String? deliveryOtp;

  bool get isPaid => paymentStatus == 'paid_upi' || paymentStatus == 'paid_cash';

  /// Reorder possible only when the mix is known.
  bool get canReorder => refillQty + containerQty >= 1;

  /// Bulk badge threshold (matches booking N 6–10 confirm band).
  bool get isBulk => refillQty + containerQty >= 6;

  Order copyWith({
    OrderState? state,
    DateTime? windowStart,
    DateTime? windowEnd,
    String? riderName,
    String? riderPhone,
    bool? refundPending,
    int? refundAmountPaise,
    bool? rated,
    int? stars,
    int? totalPaise,
    String? paymentMode,
    String? paymentStatus,
    String? deliveryOtp,
    int? stopsAhead,
    int? refillQty,
    int? containerQty,
  }) {
    return Order(
      id: id,
      state: state ?? this.state,
      windowStart: windowStart ?? this.windowStart,
      windowEnd: windowEnd ?? this.windowEnd,
      riderName: riderName ?? this.riderName,
      riderPhone: riderPhone ?? this.riderPhone,
      stopsAhead: stopsAhead ?? this.stopsAhead,
      paymentMode: paymentMode ?? this.paymentMode,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      deliveryOtp: deliveryOtp ?? this.deliveryOtp,
      itemSummary: itemSummary,
      addressLabel: addressLabel,
      waterBillPaise: waterBillPaise,
      depositDuePaise: depositDuePaise,
      capChargePaise: capChargePaise,
      prevDuesPaise: prevDuesPaise,
      paymentsPaise: paymentsPaise,
      totalPaise: totalPaise ?? this.totalPaise,
      refundPending: refundPending ?? this.refundPending,
      refundAmountPaise: refundAmountPaise ?? this.refundAmountPaise,
      rated: rated ?? this.rated,
      stars: stars ?? this.stars,
      createdAt: createdAt,
      refillQty: refillQty ?? this.refillQty,
      containerQty: containerQty ?? this.containerQty,
    );
  }
}


/// Visibility matrix (contract §4.4 + flows 3/5):
/// pre-dispatch → Cancel + Reschedule; dispatched → WhatsApp CTA only;
/// delivered → help row + rate once; cancelled → none.
extension OrderVisibility on Order {
  bool get isPreDispatch =>
      state == OrderState.placed ||
      state == OrderState.accepted ||
      state == OrderState.picked ||
      state == OrderState.packed ||
      state == OrderState.assigned;

  bool get canCancel => isPreDispatch;
  bool get canReschedule => isPreDispatch;
  bool get showWhatsAppOnly => state == OrderState.dispatched;
  bool get canRate => state == OrderState.delivered && !rated;
  bool get showHelpRow => state == OrderState.delivered;
  bool get showNoActions => state == OrderState.cancelled;
}

/// 4-step tracker index for the custom dot UI (flows flow-3):
/// 0 Confirmed (placed/accepted) · 1 Packed (picked/packed/assigned) ·
/// 2 On the way (dispatched) · 3 Delivered. Terminal fail/cancel → -1.
int trackerStep(OrderState state) {
  switch (state) {
    case OrderState.placed:
    case OrderState.accepted:
      return 0;
    case OrderState.picked:
    case OrderState.packed:
    case OrderState.assigned:
      return 1;
    case OrderState.dispatched:
      return 2;
    case OrderState.delivered:
      return 3;
    case OrderState.failed:
    case OrderState.cancelled:
    case OrderState.rejected:
      return -1;
  }
}

/// Paged result for the cursor list (server cursor, client filters locally —
/// no `q` param server-side per approved answer 6).
@immutable
class OrdersPage {
  const OrdersPage({required this.orders, this.nextCursor});
  final List<Order> orders;
  final String? nextCursor;
}

/// Backend seam (approved answer 2): F1 implements over the real base URL
/// with dart:io (no new pub deps).
/// TODO(F1): implement with real GET/POST /v1/orders* + Idempotency-Key.
abstract class OrdersRepository {
  Future<OrdersPage> fetchOrders({String? cursor});
  Future<Order> fetchOrder(String id);
  Future<Order> cancelOrder(String id, String reasonCode);
  Future<Order> rescheduleOrder(String id, DateTime windowStart);
  Future<Order> submitRating(String id, int stars);
}

/// In-memory stub for tests + pre-F1 wiring. Never ships as the real repo.
class StubOrdersRepository implements OrdersRepository {
  StubOrdersRepository([List<Order>? seed]) : _orders = List.of(seed ?? []);

  final List<Order> _orders;

  void seed(Order order) => _orders.add(order);

  @override
  Future<OrdersPage> fetchOrders({String? cursor}) async {
    const pageSize = 20;
    var start = 0;
    if (cursor != null) {
      final idx = _orders.indexWhere((o) => o.id == cursor);
      if (idx >= 0) start = idx + 1;
    }
    final slice = _orders.skip(start).take(pageSize).toList();
    final next = (start + slice.length) < _orders.length && slice.isNotEmpty
        ? slice.last.id
        : null;
    return OrdersPage(orders: slice, nextCursor: next);
  }

  @override
  Future<Order> fetchOrder(String id) async {
    for (final o in _orders) {
      if (o.id == id) return o;
    }
    throw StateError('not found: $id');
  }

  @override
  Future<Order> cancelOrder(String id, String reasonCode) async {
    final idx = _orders.indexWhere((o) => o.id == id);
    if (idx < 0) throw StateError('not found: $id');
    final current = _orders[idx];
    if (!current.canCancel) throw StateError('illegal transition');
    final updated = current.copyWith(state: OrderState.cancelled);
    _orders[idx] = updated;
    return updated;
  }

  @override
  Future<Order> rescheduleOrder(String id, DateTime windowStart) async {
    final idx = _orders.indexWhere((o) => o.id == id);
    if (idx < 0) throw StateError('not found: $id');
    final current = _orders[idx];
    if (!current.canReschedule) throw StateError('illegal transition');
    final updated = current.copyWith(
      windowStart: windowStart,
      windowEnd: windowStart.add(const Duration(minutes: 30)),
    );
    _orders[idx] = updated;
    return updated;
  }

  @override
  Future<Order> submitRating(String id, int stars) async {
    final idx = _orders.indexWhere((o) => o.id == id);
    if (idx < 0) throw StateError('not found: $id');
    final current = _orders[idx];
    if (current.state != OrderState.delivered) {
      throw StateError('rate only delivered');
    }
    if (current.rated) throw StateError('already rated');
    final updated = current.copyWith(rated: true, stars: stars);
    _orders[idx] = updated;
    return updated;
  }
}

/// Maps one server order (OrderOut, or OrderDetailOut which adds
/// tracker/rider/bill/events) onto [Order].
///
/// Wire notes (verified against workers/api schemas/orders.py +
/// services/order_service.py): `items` is [{sku: refill|container, qty}];
/// `bill` (detail only) is {water_bill, deposit_due, cap_charge, total,
/// payment_status} — it has NO prev/payments keys, so those stay 0;
/// `rider` is {name, call} once assigned, else null; `window_end` may be
/// "" (→ null); unknown `state` strings fall back to placed (never crash).
Order orderFromApi(Map<String, dynamic> json) {
  int paise(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
  DateTime? tryDate(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  var refill = 0;
  var container = 0;
  final parts = <String>[];
  final items = json['items'];
  if (items is List) {
    for (final it in items) {
      if (it is! Map) continue;
      final sku = '${it['sku'] ?? ''}';
      final qty = paise(it['qty']);
      if (qty <= 0) continue;
      if (sku == 'refill') refill += qty;
      if (sku == 'container') container += qty;
      parts.add('$qty $sku');
    }
  }

  Map<String, dynamic> section(dynamic v) =>
      v is Map<String, dynamic> ? v : Map<String, dynamic>.from(v as Map);
  final bill = json['bill'] == null
      ? const <String, dynamic>{}
      : section(json['bill']);
  final rider = json['rider'] == null
      ? const <String, dynamic>{}
      : section(json['rider']);

  return Order(
    id: '${json['id'] ?? ''}',
    state: orderStateFromString('${json['state'] ?? 'placed'}'),
    windowStart:
        tryDate(json['window_start']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    windowEnd: tryDate(json['window_end']),
    riderName: rider['name']?.toString(),
    riderPhone: (rider['phone'] ?? rider['call'])?.toString(),
    stopsAhead: json['stops_ahead'] != null
        ? (json['stops_ahead'] as num).toInt()
        : (rider['stops_ahead'] != null
            ? (rider['stops_ahead'] as num).toInt()
            : null),
    itemSummary: parts.join(' + '),
    waterBillPaise: paise(bill['water_bill'] ?? json['water_bill']),
    depositDuePaise: paise(bill['deposit_due'] ?? json['deposit_due']),
    capChargePaise: paise(bill['cap_charge'] ?? json['cap_charge']),
    totalPaise: paise(bill['total'] ?? json['total']),
    paymentMode: '${json['payment_mode'] ?? 'cod'}',
    paymentStatus:
        '${json['payment_status'] ?? bill['payment_status'] ?? 'unpaid'}',
    deliveryOtp: json['delivery_otp']?.toString(),
    refillQty: refill,
    containerQty: container,
    createdAt: tryDate(json['created_at']),
  );
}

/// Live backend repository over [ApiClient.send] (no new deps).
/// [ApiException]s (incl. NETWORK) are rethrown untouched — the controller
/// already maps failures to its offline/error states.
class ApiBackedOrdersRepository implements OrdersRepository {
  ApiBackedOrdersRepository(this._api);

  final ApiClient _api;

  @override
  Future<OrdersPage> fetchOrders({String? cursor}) async {
    final res = await _api.listOrders(cursor: cursor);
    final data = res['data'] is List ? res['data'] as List : const [];
    return OrdersPage(
      orders: data
          .whereType<Map>()
          .map((e) => orderFromApi(Map<String, dynamic>.from(e)))
          .toList(),
      nextCursor: res['next_cursor'] as String?,
    );
  }

  @override
  Future<Order> fetchOrder(String id) async =>
      orderFromApi(await _api.getOrderFull(id));

  @override
  Future<Order> cancelOrder(String id, String reasonCode) async {
    await _api.cancelOrderApi(id, reasonCode, const Uuid().v4());
    // CancelOut carries no full order — re-read the settled truth.
    return fetchOrder(id);
  }

  @override
  Future<Order> rescheduleOrder(String id, DateTime windowStart) async =>
      orderFromApi(await _api.rescheduleApi(
          id, windowStart.toIso8601String(), const Uuid().v4()));

  @override
  Future<Order> submitRating(String id, int stars) async {
    final res = await _api.submitRatingApi(id, stars);
    final fresh = await fetchOrder(id);
    final rated = res['stars'];
    return fresh.copyWith(rated: true, stars: rated is int ? rated : stars);
  }
}

enum OrdersListStatus { initial, loading, loaded, error }

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
  String? _cursor;
  bool _hasMore = false;
  bool _actionBusy = false;

  Timer? _pollTimer;
  int _pollSeconds = pollBaseSeconds;
  bool _disposed = false;

  /// Rating auto-popup fires once per delivered order view (approved answer 5).
  final Set<String> _ratingPrompted = {};

  /// Poll cadence: 60s base, exponential backoff, 300s max.
  static const int pollBaseSeconds = 60;
  static const int pollMaxSeconds = 300;

  OrdersListStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isOffline => _isOffline;
  bool get hasMore => _hasMore;
  bool get actionBusy => _actionBusy;
  int get pollSeconds => _pollSeconds;
  String get query => _query;
  int get totalCount => _all.length;
  List<Order> get allOrders => List.unmodifiable(_all);

  /// Client-side filter over id + address + item summary (no server `q`).
  List<Order> get filteredOrders {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return List.unmodifiable(_all);
    return List.unmodifiable(_all.where((o) =>
        o.id.toLowerCase().contains(q) ||
        o.addressLabel.toLowerCase().contains(q) ||
        o.itemSummary.toLowerCase().contains(q)));
  }

  Order? findById(String id) {
    for (final o in _all) {
      if (o.id == id) return o;
    }
    return null;
  }

  void setQuery(String q) {
    _query = q;
    _notify();
  }

  /// First load (skeleton in the screen while [_status] is loading).
  Future<void> load() async {
    if (_status == OrdersListStatus.loading) return;
    _status = OrdersListStatus.loading;
    _errorMessage = null;
    _notify();
    try {
      final page = await _repo.fetchOrders();
      _all
        ..clear()
        ..addAll(page.orders);
      _cursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
      _status = OrdersListStatus.loaded;
      _isOffline = false;
      _onPollSuccess();
    } catch (_) {
      _status = _all.isEmpty ? OrdersListStatus.error : OrdersListStatus.loaded;
      _errorMessage = ordersStringsHi['errorTitle'];
      _isOffline = _all.isEmpty;
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
    if (!_hasMore || cursor == null || _status == OrdersListStatus.loading) {
      return;
    }
    try {
      final page = await _repo.fetchOrders(cursor: cursor);
      _all.addAll(page.orders);
      _cursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
      _onPollSuccess();
    } catch (_) {
      _errorMessage = ordersStringsHi['errorTitle'];
      _onPollError();
    }
    _notify();
  }

  /// Detail refresh for the tracking screen (poll target).
  Future<Order?> refreshOrder(String id) async {
    try {
      final fresh = await _repo.fetchOrder(id);
      final idx = _all.indexWhere((o) => o.id == id);
      if (idx >= 0) {
        _all[idx] = fresh;
      } else {
        _all.add(fresh);
      }
      _onPollSuccess();
      _notify();
      return fresh;
    } catch (_) {
      _onPollError();
      _notify();
      return findById(id);
    }
  }

  Future<bool> cancel(String id, String reasonCode) async {
    if (_actionBusy) return false;
    _actionBusy = true;
    _notify();
    try {
      final updated = await _repo.cancelOrder(id, reasonCode);
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
    try {
      final updated = await _repo.rescheduleOrder(id, windowStart);
      _replace(updated);
      return true;
    } catch (_) {
      return false;
    } finally {
      _actionBusy = false;
      _notify();
    }
  }

  Future<bool> rate(String id, int stars) async {
    if (stars < 1 || stars > 5) return false;
    try {
      final updated = await _repo.submitRating(id, stars);
      _replace(updated);
      return true;
    } catch (_) {
      return false;
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
    final uri = Uri.parse(
      'https://wa.me/919302190067?text=${Uri.encodeComponent(orderContext)}',
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
    stopTracking();
    _pollTimer = Timer.periodic(Duration(seconds: _pollSeconds), (_) async {
      if (_disposed) return;
      await refreshOrder(id);
      // Re-arm at the (possibly backed-off) cadence.
      if (!_disposed && _pollTimer != null) {
        stopTracking();
        startTracking(id);
      }
    });
  }

  void stopTracking() {
    _pollTimer?.cancel();
    _pollTimer = null;
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
