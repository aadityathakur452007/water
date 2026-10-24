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

/// English copy for the orders feature (v1, ADR-120). Keys stay stable for a
/// later Hinglish l10n pass.
const Map<String, String> ordersStringsHi = {
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

/// User-facing lifecycle label. Raw enum names never reach the UI.
String orderStateLabel(OrderState state) => switch (state) {
  OrderState.placed => 'Placed',
  OrderState.accepted => 'Accepted',
  OrderState.picked => 'Jars picked',
  OrderState.packed => 'Packed',
  OrderState.assigned => 'Rider assigned',
  OrderState.dispatched => 'Out for delivery',
  OrderState.delivered => 'Delivered',
  OrderState.failed => 'Delivery failed',
  OrderState.cancelled => 'Cancelled',
  OrderState.rejected => 'Rejected',
};

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
  changedMind('changed_mind', 'Changed my mind'),
  duplicate('duplicate', 'Duplicate order'),
  orderedByMistake('ordered_by_mistake', 'Ordered by mistake'),
  delayed('delayed', 'Delivery is late'),
  other('other', 'Something else');

  const CancelReason(this.code, this.label);
  final String code;
  final String label;

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
      other is RescheduleSlot && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Next 7 serviceable days, starting tomorrow.
List<DateTime> nextServiceDays({int count = 7, DateTime? from}) {
  final today = from ?? DateTime.now();
  return List.generate(
    count,
    (i) => DateTime(today.year, today.month, today.day + i + 1),
  );
}

/// 30-minute slots 08:00–20:00 on one serviceable day.
List<RescheduleSlot> serviceSlotsForDay(DateTime day) {
  final base = DateTime(day.year, day.month, day.day);
  final slots = <RescheduleSlot>[];
  for (var h = 8; h < 20; h++) {
    for (final m in [0, 30]) {
      final start = base.add(Duration(hours: h, minutes: m));
      slots.add(
        RescheduleSlot(
          start: start,
          end: start.add(const Duration(minutes: 30)),
        ),
      );
    }
  }
  return slots;
}

/// Next serviceable day slots: tomorrow onward, 30-min slots 08:00–20:00.
/// 014: all days water (no Sunday skip — matches booking + GET /windows).
List<RescheduleSlot> nextServiceSlots({DateTime? from}) {
  final days = nextServiceDays(from: from);
  return serviceSlotsForDay(days.first);
}

/// ₹ formatting: paise ints, 2dp ONLY when needed (5600 → ₹56, 5650 → ₹56.50).
/// Kept as the orders-local name; the implementation is the shared formatter.
String formatRupees(int paise) => formatInr(paise);

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
    this.deliveryCodeExpiresAt,
    this.deliveryCodeState = 'none',
    this.deliveryCodeReissueAvailable = false,
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

  /// F1/034: PoD delivery code (server detail only, never the list).
  /// Only present while [deliveryCodeState] is `active`.
  final String? deliveryOtp;

  /// TTL tombstone from dispatch (UTC). Null while the stop is only assigned.
  final DateTime? deliveryCodeExpiresAt;

  /// none | active | expired | locked | unavailable | used.
  final String deliveryCodeState;

  /// True when the server says the owner may mint a replacement now.
  final bool deliveryCodeReissueAvailable;

  /// State that accounts for a 24h rollover while this screen is open.
  /// Minute precision; no per-second timer is needed for a 24h code.
  String deliveryCodeStateAt(DateTime now) {
    if (deliveryCodeState == 'active' &&
        deliveryCodeExpiresAt != null &&
        !now.isBefore(deliveryCodeExpiresAt!)) {
      return 'expired';
    }
    return deliveryCodeState;
  }

  bool get isPaid =>
      paymentStatus == 'paid_upi' || paymentStatus == 'paid_cash';

  /// Human payment truth. Never turns a partial payment into a full due.
  String get paymentLabel {
    if (paymentStatus == 'paid_upi') return 'Paid via UPI';
    if (paymentStatus == 'paid_cash') return 'Paid in cash';
    if (paymentStatus == 'partial_dues') return 'Partly paid';
    if (paymentStatus == 'refund_pending') return 'Refund pending';
    return paymentMode == 'upi' ? 'UPI pending' : 'Cash due on delivery';
  }

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
      deliveryCodeExpiresAt: deliveryCodeExpiresAt,
      deliveryCodeState: deliveryCodeState,
      deliveryCodeReissueAvailable: deliveryCodeReissueAvailable,
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

  /// Replace only the delivery-code quartet after a reissue. Kept separate
  /// from [copyWith] because a reissue can legitimately clear the code and
  /// the expiry (unlike the nullable no-op semantics of copyWith).
  Order withDeliveryCode({
    required String? code,
    required DateTime? expiresAt,
    required String state,
    required bool reissueAvailable,
  }) {
    return Order(
      id: id,
      state: state == 'used' ? OrderState.delivered : this.state,
      windowStart: windowStart,
      windowEnd: windowEnd,
      riderName: riderName,
      riderPhone: riderPhone,
      stopsAhead: stopsAhead,
      itemSummary: itemSummary,
      addressLabel: addressLabel,
      waterBillPaise: waterBillPaise,
      depositDuePaise: depositDuePaise,
      capChargePaise: capChargePaise,
      prevDuesPaise: prevDuesPaise,
      paymentsPaise: paymentsPaise,
      totalPaise: totalPaise,
      refundPending: refundPending,
      refundAmountPaise: refundAmountPaise,
      rated: rated,
      stars: stars,
      createdAt: createdAt,
      refillQty: refillQty,
      containerQty: containerQty,
      paymentMode: paymentMode,
      paymentStatus: paymentStatus,
      deliveryOtp: code,
      deliveryCodeExpiresAt: expiresAt,
      deliveryCodeState: state,
      deliveryCodeReissueAvailable: reissueAvailable,
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

/// Backend seam. [ApiBackedOrdersRepository] is the live implementation over
/// the ported [ApiClient]; the stub below exists only for tests.
abstract class OrdersRepository {
  Future<OrdersPage> fetchOrders({String? cursor});
  Future<Order> fetchOrder(String id);
  Future<Order> cancelOrder(String id, String reasonCode);
  Future<Order> rescheduleOrder(String id, DateTime windowStart);
  Future<Order> submitRating(String id, int stars);

  /// POST /orders/{id}/delivery-code/reissue → the four delivery fields.
  Future<Map<String, dynamic>> reissueDeliveryCode(String id);
}

/// In-memory stub for tests only. Never ships as the real repo.
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

  @override
  Future<Map<String, dynamic>> reissueDeliveryCode(String id) async {
    final idx = _orders.indexWhere((o) => o.id == id);
    if (idx < 0) throw StateError('not found: $id');
    final current = _orders[idx];
    if (current.deliveryCodeState == 'active') {
      throw ApiException(
        code: 'CODE_ACTIVE',
        message: 'This delivery code is still active.',
        statusCode: 409,
      );
    }
    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 24));
    final updated = current.withDeliveryCode(
      code: '654321',
      expiresAt: expiresAt,
      state: 'active',
      reissueAvailable: false,
    );
    _orders[idx] = updated;
    return {
      'delivery_otp': '654321',
      'delivery_otp_expires_at': expiresAt.toIso8601String(),
      'delivery_otp_state': 'active',
      'delivery_otp_reissue_available': false,
    };
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
  final address = json['delivery_address'] == null
      ? const <String, dynamic>{}
      : json['delivery_address'] is Map
      ? section(json['delivery_address'])
      : const <String, dynamic>{};
  final refund = json['refund'] == null
      ? const <String, dynamic>{}
      : json['refund'] is Map
      ? section(json['refund'])
      : const <String, dynamic>{};
  final addressLabel = [address['label'], address['formatted']]
      .whereType<Object>()
      .map((v) => '$v'.trim())
      .where((v) => v.isNotEmpty)
      .join(' · ');
  final orderState = orderStateFromString('${json['state'] ?? 'placed'}');
  final rawCodeState = json['delivery_otp_state']?.toString() ?? '';
  final code = json['delivery_otp']?.toString();
  final deliveryState =
      const {
        'none',
        'active',
        'expired',
        'locked',
        'unavailable',
        'used',
      }.contains(rawCodeState)
      ? rawCodeState
      : orderState == OrderState.delivered
      ? 'used'
      : (code != null && code.isNotEmpty ? 'active' : 'none');

  return Order(
    id: '${json['id'] ?? ''}',
    state: orderState,
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
    addressLabel: addressLabel,
    waterBillPaise: paise(bill['water_bill'] ?? json['water_bill']),
    depositDuePaise: paise(bill['deposit_due'] ?? json['deposit_due']),
    capChargePaise: paise(bill['cap_charge'] ?? json['cap_charge']),
    prevDuesPaise: paise(
      bill['prev_dues'] ?? bill['previous_dues'] ?? json['prev_dues'],
    ),
    paymentsPaise: paise(
      bill['payments'] ?? bill['paid'] ?? json['payments_paid'],
    ),
    totalPaise: paise(bill['total'] ?? json['total']),
    refundPending: '${refund['status'] ?? ''}' == 'pending',
    refundAmountPaise: paise(refund['amount']),
    rated: json['rated'] == true,
    stars: json['stars'] is num ? (json['stars'] as num).toInt() : null,
    paymentMode: '${json['payment_mode'] ?? 'cod'}',
    paymentStatus:
        '${json['payment_status'] ?? bill['payment_status'] ?? 'unpaid'}',
    deliveryOtp: deliveryState == 'active' ? code : null,
    deliveryCodeExpiresAt: tryDate(json['delivery_otp_expires_at']),
    deliveryCodeState: deliveryState,
    deliveryCodeReissueAvailable:
        json['delivery_otp_reissue_available'] == true,
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
      orderFromApi(
        await _api.rescheduleApi(
          id,
          windowStart.toIso8601String(),
          const Uuid().v4(),
        ),
      );

  @override
  Future<Order> submitRating(String id, int stars) async {
    final res = await _api.submitRatingApi(id, stars);
    final fresh = await fetchOrder(id);
    final rated = res['stars'];
    return fresh.copyWith(rated: true, stars: rated is int ? rated : stars);
  }

  @override
  Future<Map<String, dynamic>> reissueDeliveryCode(String id) =>
      _api.reissueDeliveryCodeApi(id);
}

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

  Future<void> load() async {
    if (_status == OrdersListStatus.loading) return;
    _status = OrdersListStatus.loading;
    _errorMessage = null;
    _loadMoreFailed = false;
    _loadMoreError = null;
    _notify();
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
      _status = _all.isEmpty ? OrdersListStatus.error : OrdersListStatus.loaded;
      _errorMessage = e is ApiException && e.isOffline
          ? 'No internet — check your connection and retry.'
          : e is ApiException && e.isServerError
          ? 'Server problem — retry in a moment.'
          : ordersStringsHi['errorTitle'];
      // Cached rows stay visible, marked stale, for network/5xx failures —
      // only a 4xx response (session/validation) is not "offline".
      _isOffline = e is ApiException && e.isOffline;
      _isServerError = e is ApiException && e.isServerError;
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

  Future<bool> cancel(String id, String reasonCode) async {
    if (_actionBusy) return false;
    _actionBusy = true;
    _notify();
    final gen = _generation;
    try {
      final updated = await _repo.cancelOrder(id, reasonCode);
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
